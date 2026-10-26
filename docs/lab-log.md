# Lab log

## Lab 01
- Working alone; chose the currency exchange topic (NBP API).
- Created the repository, wrote README, architecture sketch, user journeys, risks.
- Next: start the web service and fetch rates from NBP.

## Lab 02
- Wrote functional and non-functional requirements (docs/requirements.md).
- Wrote the network-scenario matrix (docs/network-scenarios.md).
- Decision: actions are blocked offline, reads come from a labelled cache.
- Next: start the web service and the rates endpoint.

## Lab 03
- Drew use cases, classes for the app and the server, and three flows (read, buy, lost reply) in PlantUML.
- Matched every requirement to a use case and a class.
- Made the project smaller: dropped rate history, top up and transaction history, and updated the Lab 02 requirements to match.
- Next: start the server and get rates from NBP.
