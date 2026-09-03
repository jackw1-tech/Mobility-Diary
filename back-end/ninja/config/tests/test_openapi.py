from django.test import Client


EXPECTED_TAGS = {
    "auth",
    "upload",
    "mobility",
    "privacy",
    "web-auth",
    "web-users",
}

REPRESENTATIVE_PATHS = {
    "/api/auth/register",
    "/api/privacy/settings",
    "/api/web/auth/login",
    "/api/web/users",
    "/api/mobility/trips",
    "/api/upload/trips/start",
}


def test_swagger_ui_is_available():
    response = Client(HTTP_HOST="localhost").get("/api/docs")

    assert response.status_code == 200
    assert "text/html" in response["Content-Type"]
    assert "/api/openapi.json" in response.content.decode()


def test_openapi_documents_every_backend_router():
    response = Client(HTTP_HOST="localhost").get("/api/openapi.json")

    assert response.status_code == 200
    assert response["Content-Type"] == "application/json"

    schema = response.json()
    documented_tags = {tag["name"] for tag in schema["tags"]}
    operation_tags = {
        tag
        for path_item in schema["paths"].values()
        for operation in path_item.values()
        for tag in operation.get("tags", [])
    }
    security_schemes = schema["components"]["securitySchemes"]

    assert schema["openapi"].startswith("3.")
    assert schema["info"]["title"] == "Mobility Diary API"
    assert schema["info"]["version"] == "1.0.0"
    assert schema["info"]["description"]
    assert documented_tags == EXPECTED_TAGS
    assert operation_tags == EXPECTED_TAGS
    assert REPRESENTATIVE_PATHS <= schema["paths"].keys()
    assert {"MobileBearerAuth", "WebDashboardAuth"} <= security_schemes.keys()
