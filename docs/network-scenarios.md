# Network-scenario matrix

Each row is a testable case: what goes wrong, what the user sees, what the
server holds afterwards, and the expected result we will test later.
Offline policy: actions are blocked, reads come from the cache (see
requirements.md).

| ID | Scenario | Example | User-visible state | Server state | Expected result (test) |
| --- | --- | --- | --- | --- | --- |
| S1 | Loss **before** submission | Phone goes offline, user taps "Buy 100 EUR". | Button disabled, message "You're offline. Orders need a connection." | Unchanged, nothing received. | No request is sent; no transaction in DB. (NFR4) |
| S2 | Loss **after** submission (response lost) | Order reaches the server and executes, reply is lost. | "Checking order..." (status: unknown), not "failed". | Transaction stored as confirmed. | On reconnect the app calls status by request ID and shows "Confirmed"; balance matches DB; exactly 1 transaction. (FR12, NFR7) |
| S3 | Loss after submission, request never arrived | Request lost on the wireless link before the server. | "Checking order..." | Unchanged. | Status check returns `unknown`; app shows "Not executed, try again"; no transaction. |
| S4 | Timeout | Server takes longer than 10 s. | After 10 s, for reads: "Couldn't load, showing cached data"; for actions: "Checking order...". | Read: nothing changed. Action: may or may not be executed. | App never shows success without server confirmation; follow-up status check gives the true result. (NFR1) |
| S5 | Delayed response | Server replies after 8 s. | Spinner, then normal result. | Normal. | Result shown once; no duplicate request sent while waiting. |
| S6 | Retry of a read | First two rate requests fail. | Spinner, then rates. | Unchanged. | Third attempt succeeds; at most 3 attempts. (NFR6) |
| S7 | Retry of an action (user taps again / app resends) | Same order sent twice with the same request ID. | One "Confirmed". | One transaction. | Server returns the stored result for the duplicate; balance changes once. (FR11, NFR5) |
| S8 | Cached display | App opened offline. | Rates with "Cached, from 2026-10-14" label; wallet with "last known" label; actions disabled. | Unchanged. | Cache label and date visible; no action possible. (NFR2, NFR4) |
| S9 | Stale data | Cache is from 2 working days ago, or NBP hasn't published today. | Rates marked "stale". | Server rate copy has an older effective date. | Stale label shown; an order sent with a stale rate is rejected with the new rate. (NFR3, FR13) |
| S10 | Reconnection | Connection returns after S2 or S8. | Labels disappear, fresh rates and balance, pending order resolved. | Unchanged by reconnect. | Within 5 s app data matches the server. (NFR7) |
| S11 | Competing data-changing requests (same user, two devices) | Phone and tablet both sell all 100 EUR at the same moment. | One device: "Confirmed". Other: "Insufficient balance". | One sell stored, EUR = 0. | Exactly one succeeds; balance never negative. (NFR8, FR9) |
| S12 | Competing: rate changes during order | NBP publishes a new rate between display and submit. | "Rate changed to X. Confirm?" | No transaction. | Order rejected with new rate; nothing executes until the user confirms. (FR13) |
| S13 | Double tap | User taps "Buy" twice quickly. | One "Checking...", then one "Confirmed". | One transaction. | The button is disabled after the first tap; both taps would share one request ID anyway. (FR11) |
| S14 | NBP API unavailable | Server can't reach NBP. | Rates with "stale" label. | Serves last stored rates with their date. | App works with labelled stale rates; orders use the server's last rate or are rejected per FR13. |
