"""One error format for the whole API, so the phone can react to `code`.

Every error body looks like:

    {"error": {"code": "INVALID_AMOUNT",
               "message": "amount must be greater than 0",
               "details": [{"field": "amount", "problem": "..."}]}}

`code` is stable and meant for the app (switch on it). `message` is for
people (logs, debugging). `details` is only there for input errors.
Order rejections (RATE_CHANGED, INSUFFICIENT_FUNDS) are not errors in this
sense: they are saved order results and keep the format from docs/api.md.
"""
from fastapi import FastAPI, Request
from fastapi.exceptions import RequestValidationError
from fastapi.responses import JSONResponse
from starlette.exceptions import HTTPException as StarletteHTTPException


class ApiError(Exception):
    def __init__(self, status: int, code: str, message: str, details: list | None = None):
        self.status = status
        self.code = code
        self.message = message
        self.details = details or []


def error_body(code: str, message: str, details: list | None = None) -> dict:
    body = {"code": code, "message": message}
    if details:
        body["details"] = details
    return {"error": body}


def _field_name(loc: tuple) -> str:
    # loc looks like ("body", "amount") or ("path", "request_id")
    parts = [str(p) for p in loc if p not in ("body", "query", "path", "header")]
    return ".".join(parts) or "body"


def install_handlers(app: FastAPI) -> None:
    @app.exception_handler(ApiError)
    async def _api_error(_: Request, exc: ApiError):
        return JSONResponse(error_body(exc.code, exc.message, exc.details), status_code=exc.status)

    @app.exception_handler(RequestValidationError)
    async def _validation(_: Request, exc: RequestValidationError):
        details = []
        for err in exc.errors():
            if err.get("type") == "json_invalid":
                return JSONResponse(
                    error_body("MALFORMED_JSON", "Request body is not valid JSON."), status_code=400
                )
            details.append({"field": _field_name(err.get("loc", ())), "problem": err.get("msg", "invalid")})
        return JSONResponse(
            error_body("VALIDATION_ERROR", "Some fields are missing or have the wrong type.", details),
            status_code=400,
        )

    @app.exception_handler(StarletteHTTPException)
    async def _http(_: Request, exc: StarletteHTTPException):
        codes = {404: "NOT_FOUND", 405: "METHOD_NOT_ALLOWED"}
        return JSONResponse(
            error_body(codes.get(exc.status_code, "HTTP_ERROR"), str(exc.detail)),
            status_code=exc.status_code,
        )

    @app.exception_handler(Exception)
    async def _unexpected(_: Request, exc: Exception):
        # Never send a stack trace to the phone.
        return JSONResponse(error_body("INTERNAL_ERROR", "Unexpected server error."), status_code=500)
