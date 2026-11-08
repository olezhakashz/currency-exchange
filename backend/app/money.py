"""Conversions between Decimal values in the API and integers in the database."""
from decimal import ROUND_HALF_UP, Decimal

CENT = Decimal("0.01")
RATE_STEP = Decimal("0.0001")


def to_minor(amount: Decimal) -> int:
    """100.25 -> 10025 (exact; caller has already checked there are at most 2 decimals)."""
    return int((amount * 100).to_integral_value())


def from_minor(minor: int) -> float:
    return float(Decimal(minor) / 100)


def rate_to_e4(rate: Decimal) -> int:
    return int((rate * 10000).to_integral_value())


def rate_from_e4(e4: int) -> Decimal:
    return (Decimal(e4) / 10000).quantize(RATE_STEP)


def pln_value_minor(amount_minor: int, rate_e4: int) -> int:
    """PLN value of a foreign amount, rounded half-up to whole grosz."""
    value = (Decimal(amount_minor) / 100) * (Decimal(rate_e4) / 10000)
    return to_minor(value.quantize(CENT, rounding=ROUND_HALF_UP))


def decimals(value: Decimal) -> int:
    exp = value.normalize().as_tuple().exponent
    return -exp if isinstance(exp, int) and exp < 0 else 0
