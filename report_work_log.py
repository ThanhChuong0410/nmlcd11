import requests
from requests.auth import HTTPBasicAuth
from datetime import datetime
from dateutil import parser
import json

# ========= CONFIG =========
JIRA_DOMAIN = "https://godeyes.atlassian.net"
EMAIL = "chuongthanh0410@gmail.com"
API_TOKEN = ""
START_DATE = "2025-11-15"  # YYYY-MM-DD
# ==========================

auth = HTTPBasicAuth(EMAIL, API_TOKEN)
headers = {"Accept": "application/json"}

start_date = datetime.strptime(START_DATE, "%Y-%m-%d")

def jira_search(start_at=0) -> dict:
    jql = f'worklogAuthor = currentUser() AND worklogDate >= "{START_DATE}"'
    url = f"{JIRA_DOMAIN}/rest/api/3/search/jql"
    params = {
        "jql": jql,
        "startAt": start_at,
        "maxResults": 100,
        "fields": "summary"
    }
    return requests.get(url, headers=headers, auth=auth, params=params).json()

def get_worklogs(issue_key):
    url = f"{JIRA_DOMAIN}/rest/api/3/issue/{issue_key}/worklog"
    return requests.get(url, headers=headers, auth=auth).json().get("worklogs", [])

total_seconds = 0
rows = []

start_at = 0
while True:
    result = jira_search(start_at)

    issues = result.get("issues", [])
    if not issues:
        break

    for issue in issues:
        key = issue["key"]
        summary = issue["fields"]["summary"]
        worklogs = get_worklogs(key)

        for wl in worklogs:
            author = wl["author"]["emailAddress"]
            started = parser.parse(wl["started"]).replace(tzinfo=None)

            # print(json.dumps(wl, indent=2))  # Debug: print worklog details

            if author == EMAIL and started >= start_date:
                seconds = wl["timeSpentSeconds"]
                total_seconds += seconds

                rows.append({
                    "date": started.strftime("%Y-%m-%d %H:%M:%S"),
                    "issue": key,
                    "summary": summary,
                    "time_hours": round(seconds / 3600, 2),
                    "comment": wl.get("comment", {}).get("content", [{}])[0]
                                .get("content", [{}])[0]
                                .get("text", "")
                })

    if not result.get("maxResults"):
        if result.get("isLast"):
            break

    start_at += result["maxResults"]
    if start_at >= result["total"]:
        break

# ========= OUTPUT =========
print("\n############## WORKLOG DETAIL ##############")
for r in rows:
    print(
        f"{r['date']} | {r['issue']} | {r['summary']} | "
        f"{r['time_hours']}h | {r['comment']}"
    )

print("\n############## TOTAL ##############")
print(f"Total time: {round(total_seconds / 3600, 2)} hours ~ {round(total_seconds / 3600 / 8, 2)} days")
