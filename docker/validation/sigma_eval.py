#!/usr/bin/env python3
"""sigma_eval.py — a nested-field-preserving Sigma-over-JSON evaluator.

The cloud-plane twin of zircolite. zircolite is EVTX-oriented: its flattener
collapses a nested/dotted event path to the last key with underscores stripped
(verified with --keepflat: `gcp.audit.method_name` -> `methodname`), so cloud
Sigma rules that match on dotted field names (`resource.type`, `objectRef.resource`,
`gcp.audit.method_name`) can never fire through it. This evaluator matches a rule
against a JSON event by walking pysigma's OWN parsed, fully-resolved condition
tree — so field modifiers (contains/startswith/endswith/all) and the condition
logic come from the authoritative parser, not a re-implementation — and does a
nested-dict lookup on the dotted field name, which is exactly what zircolite drops.

It is deliberately tiny: it supports only what the cloud corpus uses — AND / OR /
NOT over `field = value` leaves, with string (incl. wildcards), number, and null
values, and dotted-path field lookup into nested JSON. Anything outside that
surface (regex modifiers, `|re`, correlation) raises rather than guessing, so an
unsupported rule fails loudly instead of silently passing.

CLI:  sigma_eval.py <rule.yml> <event.jsonl>
      exit 0 and print "FIRE <id>" if ANY event in the JSONL fires the rule,
      exit 1 and print "NOFIRE <id>" if none do. --expect <id> asserts the id.
"""
import argparse
import json
import re
import sys

from sigma.collection import SigmaCollection
from sigma.conditions import (
    ConditionAND,
    ConditionFieldEqualsValueExpression,
    ConditionNOT,
    ConditionOR,
)
from sigma.types import SigmaBool, SigmaNull, SigmaNumber, SigmaString, SpecialChars


def _string_to_regex(sv):
    """SigmaString -> anchored, case-insensitive regex.

    pysigma has already baked the field modifiers into the value: `|contains`
    wraps the token in WILDCARD_MULTI on both sides, `|startswith`/`|endswith`
    add one, so a plain equals and a modified match both reduce to a wildcard
    string here. We translate its parts to regex rather than re-deriving intent.
    """
    parts = []
    for p in sv.s:
        if p == SpecialChars.WILDCARD_MULTI:
            parts.append(".*")
        elif p == SpecialChars.WILDCARD_SINGLE:
            parts.append(".")
        else:
            parts.append(re.escape(p))
    return "^" + "".join(parts) + "$"


def _lookup(event, field):
    """Dotted-path lookup into nested JSON — the bit zircolite can't do.

    `objectRef.resource` descends event['objectRef']['resource']. A list met
    mid-path is fanned out (Sigma's "any element" semantics), so
    `requestObject.spec.containers.securityContext.privileged` reaches into a
    list of container objects. Returns None if the path resolves nowhere; a
    single value if exactly one leaf is reached; else the list of leaf values
    (which _match_value already treats as "match if any").
    """
    cur = [event]
    for key in field.split("."):
        nxt = []
        for node in cur:
            if isinstance(node, list):
                for item in node:
                    if isinstance(item, dict) and key in item:
                        nxt.append(item[key])
            elif isinstance(node, dict) and key in node:
                nxt.append(node[key])
        cur = nxt
    if not cur:
        return None
    return cur[0] if len(cur) == 1 else cur


def _match_value(event_value, sigma_value):
    """Does the event's field value match this Sigma value? Lists match if any
    element matches (Sigma field-list semantics)."""
    values = event_value if isinstance(event_value, list) else [event_value]
    if isinstance(sigma_value, SigmaString):
        rx = _string_to_regex(sigma_value)
        return any(v is not None and re.match(rx, str(v), re.IGNORECASE) for v in values)
    if isinstance(sigma_value, SigmaBool):
        return any(v is sigma_value.boolean for v in values)
    if isinstance(sigma_value, SigmaNumber):
        return any(str(v) == str(sigma_value.number) for v in values)
    if isinstance(sigma_value, SigmaNull):
        return event_value is None
    raise ValueError(f"unsupported Sigma value type: {type(sigma_value).__name__}")


def _eval(node, event):
    if isinstance(node, ConditionAND):
        return all(_eval(a, event) for a in node.args)
    if isinstance(node, ConditionOR):
        return any(_eval(a, event) for a in node.args)
    if isinstance(node, ConditionNOT):
        return not _eval(node.args[0], event)
    if isinstance(node, ConditionFieldEqualsValueExpression):
        return _match_value(_lookup(event, node.field), node.value)
    raise ValueError(f"unsupported condition node: {type(node).__name__}")


def _base_rule(rule_path):
    """First rule with a detection block. A correlation file (multi-doc) also
    carries a SigmaCorrelationRule with no `.detection`; we validate the base
    per-event detection here — the stateful count/timespan aggregation is out of
    scope for a single-event matcher (documented, not silently claimed)."""
    for rule in SigmaCollection.from_yaml(open(rule_path).read()).rules:
        if getattr(rule, "detection", None) is not None:
            return rule
    raise ValueError(f"no rule with a detection block in {rule_path}")


def rule_fires(rule_path, event):
    """True if `event` (a dict) fires the rule at `rule_path`."""
    rule = _base_rule(rule_path)
    tree = rule.detection.parsed_condition[0].parse()
    return _eval(tree, event)


def rule_id(rule_path):
    return str(_base_rule(rule_path).id)


def _load_events(fixture_path):
    events = []
    with open(fixture_path) as fh:
        for line in fh:
            line = line.strip()
            if line and not line.startswith("#"):
                events.append(json.loads(line))
    return events


def main(argv=None):
    ap = argparse.ArgumentParser(description="Evaluate a Sigma rule over JSONL events.")
    ap.add_argument("rule", help="path to the Sigma rule .yml")
    ap.add_argument("fixture", help="path to the JSON-lines event fixture")
    ap.add_argument("--expect", help="assert this rule id fired", default=None)
    args = ap.parse_args(argv)

    rid = rule_id(args.rule)
    if args.expect and args.expect != rid:
        print(f"NOFIRE {rid} — expected id {args.expect} does not match rule id", file=sys.stderr)
        return 1

    events = _load_events(args.fixture)
    fired = any(rule_fires(args.rule, ev) for ev in events)
    if fired:
        print(f"FIRE {rid}")
        return 0
    print(f"NOFIRE {rid}")
    return 1


if __name__ == "__main__":
    sys.exit(main())
