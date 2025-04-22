# Microservices Demo Error Documentation

This document tracks the errors found in the microservices demo and their solutions.

## Error Categories

### Application Errors

| Service | Error Description | Status | Solution | Reference |
|---------|------------------|--------|----------|-----------|
| Cart Service | Unable to add loafers to cart | ✅ Fixed | Remove exception when loafers are added to cart | [Slack Thread](https://fuzzy-labs.slack.com/archives/C08M5SMJ0KW/p1744896330504309) |
| Payment Service | Order placement with valid credit card | ❌ Unresolved | Exception should be thrown for valid credit cards | No message, stuck in loop |
| Currency Service | GBP currency conversion | ✅ Fixed | Add conversion rate for GBP | [Slack Thread](https://fuzzy-labs.slack.com/archives/C08M5SMJ0KW/p1744896844011919) |
| Product Catalog | Negative price for ducks | ✅ Fixed | Fix duck's unit price in `products.json` | [Slack Thread](https://fuzzy-labs.slack.com/archives/C08M5SMJ0KW/p1744897001392409) |

### System Errors

| Error Description | Status | Solution | Reference |
|------------------|--------|----------|-----------|
| Node crash due to k8s memory misconfiguration | Pending | TBD | TBD |

## Status Legend
- ✅ Fixed: Error has been identified and resolved
- ❌ Unresolved: Error has been identified but not yet fixed
- Pending: Error is under investigation

## Notes
- Each error includes a reference link to relevant discussion threads where available
- Solutions are documented with specific implementation details
- System errors are tracked separately from application errors for better organization