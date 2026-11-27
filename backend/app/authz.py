"""Authorisation: what an identified caller may do (Lab 07).

All rules are here, in one small module, and every endpoint calls one of them
before it touches data. The app hiding a button is only convenience; these
checks are what actually protects the data.

| Resource                     | Rule                                         | Refused with          |
| ---------------------------- | -------------------------------------------- | --------------------- |
| rates (read)                 | anyone, no token (public, read-only)         | -                     |
| own account, wallet, orders  | the token's user; the id is never taken from | 401 without token     |
|                              | the request body                             |                       |
| /users/{id}, /users/{id}/... | that user, or an ADMIN                       | 403 FORBIDDEN         |
| /orders/{requestId}          | the user who placed it                       | 404 NOT_FOUND (as if  |
|                              |                                              | it did not exist)     |
| /admin/...                   | role ADMIN (read from the database)          | 403 FORBIDDEN         |
"""
from .auth import Caller
from .errors import ApiError


def require_admin(caller: Caller) -> None:
    if not caller.is_admin:
        raise ApiError(403, "FORBIDDEN", "This needs the ADMIN role.")


def require_self_or_admin(caller: Caller, user_id: int) -> None:
    # Checked before the user is looked up, so a refusal tells nothing about
    # whether that user id exists.
    if caller.id != user_id and not caller.is_admin:
        raise ApiError(403, "FORBIDDEN", "You can only access your own account.")
