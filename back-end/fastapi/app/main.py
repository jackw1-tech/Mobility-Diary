from fastapi import FastAPI

app = FastAPI(title="Mobility Diary HAR Service")


@app.get("/health")
def health() -> dict[str, str]:
    return {"status": "ok", "service": "fastapi-har"}
