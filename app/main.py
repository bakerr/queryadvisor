from __future__ import annotations

import time
import uuid

from fastapi import FastAPI, Form, Request
from fastapi.responses import HTMLResponse
from fastapi.staticfiles import StaticFiles
from fastapi.templating import Jinja2Templates

from app.config import get_connection
from app.metadata.collector import collect_metadata
from app.models import ReportCard
from app.parser.extractor import extract_query_profiles
from app.rules.engine import evaluate_rules
from app.scoring.scorer import score_findings

app = FastAPI(title="QueryAdvisor")
app.mount("/static", StaticFiles(directory="static"), name="static")
templates = Jinja2Templates(directory="app/templates")

_results: dict[str, tuple[float, ReportCard]] = {}
_TTL = 1800.0


def _prune():
    now = time.time()
    stale = [k for k, (ts, _) in _results.items() if now - ts > _TTL]
    for k in stale:
        del _results[k]


@app.get("/", response_class=HTMLResponse)
async def index(request: Request):
    return templates.TemplateResponse(request, "index.html")


@app.get("/api/databases")
async def list_databases():
    conn = get_connection("master")
    cursor = conn.cursor()
    cursor.execute("SELECT name FROM sys.databases WHERE state_desc = 'ONLINE' ORDER BY name")
    databases = [row[0] for row in cursor.fetchall()]
    conn.close()
    return {"databases": databases}


@app.get("/api/databases/options", response_class=HTMLResponse)
async def list_databases_options(request: Request):
    conn = get_connection("master")
    cursor = conn.cursor()
    cursor.execute("SELECT name FROM sys.databases WHERE state_desc = 'ONLINE' ORDER BY name")
    databases = [row[0] for row in cursor.fetchall()]
    conn.close()
    options_html = "".join(f'<option value="{db}">{db}</option>' for db in databases)
    return HTMLResponse(options_html)


@app.post("/api/analyze", response_class=HTMLResponse)
async def analyze(
    request: Request,
    sql: str = Form(...),
    database: str = Form(...),
    username: str = Form(...),
):
    _prune()
    profiles = extract_query_profiles(sql)
    real_tables = list({
        f"{t.schema_name}.{t.name}"
        for p in profiles for t in p.tables if not t.is_temp
    })
    bundle = collect_metadata(real_tables, database)
    all_findings = []
    for profile in profiles:
        all_findings.extend(evaluate_rules(profile, bundle))
    report_card = score_findings(all_findings)

    request_id = str(uuid.uuid4())
    _results[request_id] = (time.time(), report_card)

    return templates.TemplateResponse(
        request,
        "partials/results.html",
        {"report_card": report_card, "request_id": request_id, "view": "list"},
    )


@app.get("/api/results/{request_id}/list", response_class=HTMLResponse)
async def results_list(request: Request, request_id: str):
    entry = _results.get(request_id)
    if not entry:
        return HTMLResponse("<p>Result expired. Please re-analyze.</p>", status_code=410)
    _, report_card = entry
    return templates.TemplateResponse(
        request,
        "partials/findings_list.html",
        {"report_card": report_card, "request_id": request_id},
    )


@app.get("/api/results/{request_id}/annotated", response_class=HTMLResponse)
async def results_annotated(request: Request, request_id: str):
    entry = _results.get(request_id)
    if not entry:
        return HTMLResponse("<p>Result expired. Please re-analyze.</p>", status_code=410)
    _, report_card = entry
    return templates.TemplateResponse(
        request,
        "partials/annotated_sql.html",
        {"report_card": report_card, "request_id": request_id},
    )
