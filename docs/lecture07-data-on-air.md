# Week 07 lecture: DATA ON AIR, applied to this project

Short answers to the lecture's worked discussion and check questions, and
what they mean for the currency exchange service.

## How it relates to Lab 07

The lecture's point "broadcast distribution does not establish transaction
authority" is the line drawn in Lab 07:

| Data | Kind | Could go on air? | Access |
| --- | --- | --- | --- |
| NBP mid rates (table A) | Same for everyone, read-only, changes once per working day | Yes: one transmission serves every listener | Public `GET /rates`, no token |
| Wallet balances, orders | Personal, changes with each order | No: private, and a broadcast copy would be stale | Token, owner only |
| Buy / sell | A transaction | No: needs an individual request, an identified caller, the current rate and an answer | `POST /orders`, token, `requestId` |

A rate heard on air is only the `seenRate` the user saw. The service still
checks it against the stored rate (`RATE_CHANGED`) and runs the order for the
identified caller only.

## Worked discussion: a broadcast cycle for one district

Example: the city centre of a town with a train station and an exchange
office (a "kantor").

| Order in cycle | Category | Size | How it becomes stale | Repeat |
| --- | --- | --- | --- | --- |
| 1 | Index: what follows, version stamps, time of the next cycle | very small | every cycle | every cycle, first |
| 2 | Exchange rates for the 8 currencies of table A, with the NBP date | small | when NBP publishes (about 12:15 Warsaw time on working days); the date says how old it is | every cycle |
| 3 | Opening hours and queue length at the local exchange office and ATMs | small | queue: minutes; hours: rarely | every cycle; queue updated each cycle |
| 4 | Paid announcements (offers from local shops) | larger | campaign end | once every few cycles, only in spare airtime |

Essential information goes first and is repeated most often; paid content
fills only what is left.

**Compared with separate requests from every listener.** With 1 000 phones
in the district, separate requests mean 1 000 requests and 1 000 identical
answers for the same table, and the load grows with the number of users.
The broadcast costs the same airtime for 1 or 10 000 listeners, and the phone
sends nothing (saves its transmit power, and works where uploading is slow).
The cost: a phone waits up to one cycle for the item it needs, and airtime
spent on items nobody wants is wasted. Broadcast wins for small, popular data
needed by many (rates, local notices); separate requests win for rare or
personal data (one user's wallet).

**When can the phone reduce its listening power?** Once it has read the index
at the start of a cycle, it knows when the items it wants are sent and their
version stamps. It sleeps until its item's slot, wakes just before it, and
sleeps again. If the version stamp of the rates hasn't changed since last
time (for example, the whole evening after NBP published), it can skip the
item and sleep until the next index. It must wake for the index of every
cycle, or it misses changes.

## Check understanding

1. **Which data benefits most from shared transmission?** Data that many
   nearby users want at the same time, that is the same for all of them,
   small, read-only and not private: exchange rates, local timetables,
   parking availability for that district, warnings. Personal data and
   transactions do not belong there.
2. **Why do cadence and freshness interact?** A broadcast item is at most one
   cycle old when it is heard, plus the time the receiver waited. If the
   data changes faster than the cycle repeats it, listeners get outdated
   values (old parking availability is misleading). A shorter cycle keeps
   data fresh but leaves less airtime for other items and makes phones wake
   more often. So the cadence of each item should follow how fast it
   changes: NBP rates once per cycle is plenty (they change daily); queue
   lengths need every cycle.
3. **How could paid content conflict with a service priority?** Paid
   announcements earn money, so there is pressure to give them more or
   earlier airtime. Every second they use makes the cycle longer, so
   essential items (rates, safety notices) repeat less often, become staler
   and phones wait and listen longer, using more battery. Paid content must
   be labelled, kept apart from essential information, and capped to the
   airtime left after essential items.
