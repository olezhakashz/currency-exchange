# Initial risk list

| # | Risk | Effect | How we plan to handle it |
| --- | --- | --- | --- |
| R1 | **Stale rates**: phone shows cached rates after losing connection, or NBP has not published today's table yet (weekends, holidays). | User sees or trades on an old rate. | Always show the rate's effective date; label offline data; block or re-check the rate on the server before executing an order. |
| R2 | **Uncertain outcome after a lost response**: the order reached the server but the reply was lost. | User may not know if money moved, and may tap again and buy twice. | Unique `order_id` per order (idempotent), server ignores duplicates; app asks for order status after reconnecting. |
| R3 | NBP API down or slow. | No fresh rates. | Server keeps the last copy with its date and serves it with a "stale" flag; timeouts on the NBP call. |
| R4 | Slow or flaky wireless link. | Requests time out, bad experience. | Short timeouts, limited retries with backoff, small responses. |
| R5 | Rate changes between showing and buying. | User pays a different price than shown. | Order carries the rate the user saw; server rejects if it differs and asks to confirm. |
| R6 | Working alone: too much work for one person. | Labs fall behind. | Keep the app small, finish the backend first, commit after each lab. |
| R7 | Wallet data leaked or tampered with. | Wrong balances. | Login token, HTTPS, server is the only owner of balances. |
