#!/usr/bin/env bash
# Tests for detect.sh's proposed classification, one mini-repo per shape.
set -euo pipefail
here="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
. "$here/helpers.bash"
detect="$here/../detect.sh"
work="$(mktemp -d)"; trap 'rm -rf "$work"' EXIT

mk() { # <repo> <path> [content]
  mkdir -p "$(dirname "$work/$1/$2")"
  printf '%s\n' "${3:-}" > "$work/$1/$2"
}
prop() { bash "$detect" "$work/$1" | jq -r ".proposed.$2"; }

# Kubernetes Python service with PostgreSQL
mk k8s pyproject.toml '[project]
dependencies = ["fastapi==0.110.0", "psycopg[binary]==3.1.18"]'
mk k8s src/app/main.py 'print(1)'
mk k8s charts/app/Chart.yaml 'name: app'
mk k8s README.md 'Status: maintained'
assert_eq "k8s type" "service" "$(prop k8s type)"
assert_eq "k8s target" "kubernetes" "$(prop k8s deployment_target)"
assert_eq "k8s database" "postgresql" "$(prop k8s database)"
assert_eq "k8s status from README" "maintained" "$(prop k8s status)"
assert_eq "k8s not lightweight" "false" "$(prop k8s lightweight)"

# Fly.io Go service with SQLite
mk fly go.mod 'module x
require modernc.org/sqlite v1.29.0'
mk fly cmd/server/main.go 'package main // http.ListenAndServe'
mk fly fly.toml 'app = "x"'
assert_eq "fly type" "service" "$(prop fly type)"
assert_eq "fly target" "fly" "$(prop fly deployment_target)"
assert_eq "fly database" "sqlite" "$(prop fly database)"
assert_eq "fly lightweight proposed" "true" "$(prop fly lightweight)"
assert_eq "fly default status" "active" "$(prop fly status)"

# Cloudflare Worker with D1
mk cf package.json '{"name":"w","devDependencies":{"wrangler":"3.0.0"}}'
mk cf src/index.ts 'export default {}'
mk cf wrangler.toml '[[d1_databases]]
binding = "DB"'
assert_eq "cf target" "cloudflare" "$(prop cf deployment_target)"
assert_eq "cf database" "d1" "$(prop cf database)"

# Go CLI
mk cli go.mod 'module tool'
mk cli cmd/tool/main.go 'package main'
assert_eq "cli type" "cli" "$(prop cli type)"
assert_eq "cli target" "none" "$(prop cli deployment_target)"
assert_eq "cli database" "none" "$(prop cli database)"

# Python library
mk lib pyproject.toml '[project]
name = "lib"'
mk lib src/lib/__init__.py ''
assert_eq "library type" "library" "$(prop lib type)"

# Infrastructure: manifests only
mk infra apps/argo.yaml 'apiVersion: argoproj.io/v1alpha1
kind: Application'
assert_eq "infra type" "infrastructure" "$(prop infra type)"

# Existing tag is surfaced so classify can offer it as the default
mk tagged go.mod 'module tool'
mk tagged .nyx.yml 'engineering_standards:
  type: library'
assert_eq "existing tag surfaced" "library" "$(bash "$detect" "$work/tagged" | jq -r .existing.type)"

# Monorepo: manifests and the database live in workspace members; the tests'
# SQLite fixture alone must not count. Fly is production, a chart is pre-prod.
mk mono pyproject.toml '[tool.uv.workspace]
members = ["apps/*"]'
mk mono apps/api/pyproject.toml '[project]
dependencies = ["fastapi==0.110.0", "sqlalchemy==2.0.30"]'
mk mono apps/api/src/app/db.py 'URL = "sqlite:////data/app.db"'
mk mono apps/api/tests/test_db.py 'import sqlite3'
mk mono fly.toml 'app = "x"'
mk mono deploy/k8s/app/Chart.yaml 'name: app'
assert_eq "monorepo type" "service" "$(prop mono type)"
assert_eq "monorepo database from workspace source" "sqlite" "$(prop mono database)"
assert_eq "monorepo target prefers fly" "fly" "$(prop mono deployment_target)"
assert_contains "monorepo target reason names the chart" "deploy/k8s/app" "$(bash "$detect" "$work/mono" | jq -r .reasons.deployment_target)"
mk testonly pyproject.toml '[project]
name = "x"'
mk testonly src/x/__init__.py ''
mk testonly tests/test_x.py 'import sqlite3'
assert_eq "SQLite used only by tests is not a database" "none" "$(prop testonly database)"

# Every proposal carries a reason for every field
reasons_ok="$(bash "$detect" "$work/k8s" | jq '(.proposed | keys) == (.reasons | keys)')"
assert_eq "a reason for every proposed field" "true" "$reasons_ok"

finish
