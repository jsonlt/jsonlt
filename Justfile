set shell := ['uv', 'run', '--frozen', 'bash', '-euxo', 'pipefail', '-c']
set unstable
set positional-arguments

project := "jsonlt"
package := "jsonlt"
pnpm := "pnpm exec"

spec_dir := "spec"
conformance_dir := "conformance"
build_dir := "build"
spec_build_dir := "build/latest"
conformance_build_dir := "build/latest/tests"

# Build all specifications
build: build-spec build-conformance-spec build-conformance-suite
  cp _redirects {{build_dir}}/

# Build the specification
build-spec: clean-spec
  mkdir -p {{spec_build_dir}}
  bikeshed spec {{spec_dir}}/index.bs {{spec_build_dir}}/index.html
  cp -r {{spec_dir}}/images {{spec_build_dir}}/

# Build the conformance test suite documentation
build-conformance-spec: clean-conformance-spec
  mkdir -p {{conformance_build_dir}}
  bikeshed spec {{conformance_dir}}/index.bs {{conformance_build_dir}}/index.html
  cp -r {{spec_dir}}/images {{conformance_build_dir}}/

# Build the conformance test suite (schemas and test files)
build-conformance-suite:
  mkdir -p {{conformance_build_dir}}/schemas
  mkdir -p {{conformance_build_dir}}/suite
  cp -r {{conformance_dir}}/schemas/* {{conformance_build_dir}}/schemas/
  # Convert JSONC test files to JSON for distribution (strips comments)
  for f in {{conformance_dir}}/suite/*.jsonc; do \
    python3 scripts/strip_jsonc_comments.py < "$f" | python3 -c "import json, sys; data = json.load(sys.stdin); json.dump(data, open(sys.argv[1], 'w'), indent=2)" "{{conformance_build_dir}}/suite/$(basename "$f" .jsonc).json"; \
  done

# Clean all build artifacts
clean: clean-spec clean-conformance-spec
  rm -fr {{build_dir}}

# Clean specification build artifacts
clean-spec:
  rm -fr {{spec_build_dir}}

# Clean conformance build artifacts
clean-conformance-spec:
  rm -fr {{conformance_build_dir}}

# List available recipes
default:
  @just --list

# Deploy to production
deploy:
  {{pnpm}} wrangler deploy

# Deploy to preview environment
deploy-preview pr_number:
  {{pnpm}} wrangler deploy --env preview --name jsonlt-spec-preview-pr-{{pr_number}}

# Install all dependencies (Python + Node.js)
install: install-node install-python

# Install only Node.js dependencies
install-node:
  #!/usr/bin/env bash
  pnpm install --frozen-lockfile

# Install pre-commit hooks
install-prek:
  prek install

# Install only Python dependencies
install-python:
  #!/usr/bin/env bash
  uv sync --frozen

# Lint prose in documentation
lint-prose:
  vale **/*.md

# Lint the specification
lint-spec:
  vale spec/index.bs

# Lint conformance documentation
lint-conformance: lint-conformance-spec lint-conformance-schemas lint-conformance-tests

# Lint conformance test suite schemas against their metaschema
lint-conformance-schemas:
  check-jsonschema --check-metaschema conformance/schemas/**/*.json

# Lint the conformance test suite documentation
lint-conformance-spec:
  vale conformance/index.bs

# Lint conformance test files against the suite schema
# Strips // and /* */ comments from JSONC files before validation
lint-conformance-tests:
  mkdir -p .lint-tmp
  for f in conformance/suite/*.jsonc; do \
    python3 scripts/strip_jsonc_comments.py < "$f" | python3 -c "import json, sys; data = json.load(sys.stdin); json.dump(data, open('.lint-tmp/' + sys.argv[1], 'w'))" "$(basename "$f" .jsonc).json"; \
  done
  check-jsonschema --schemafile conformance/schemas/v1/suite.schema.json .lint-tmp/*.json
  rm -rf .lint-tmp

# Run pre-commit hooks on changed files
prek:
  prek

# Run pre-commit hooks on all files
prek-all:
  prek run --all-files

# Serve the specification locally
serve-spec:
  bikeshed serve {{spec_dir}}/index.bs

# Serve the conformance test suite documentation locally
serve-conformance-spec:
  bikeshed serve {{conformance_dir}}/index.bs

# Run all validations
validate: validate-html validate-links

# Validate conformance HTML markup
validate-conformance-html:
  java -jar $(pnpm exec node -p "String(require('vnu-jar'))") --also-check-css {{conformance_build_dir}}/index.html

# Check conformance docs for broken links
validate-conformance-links:
  linkchecker {{conformance_build_dir}}/index.html

# Validate all HTML markup
validate-html: validate-spec-html validate-conformance-html

# Check all docs for broken links
validate-links: validate-spec-links validate-conformance-links

# Validate spec HTML markup
validate-spec-html:
  java -jar $(pnpm exec node -p "String(require('vnu-jar'))") --also-check-css {{spec_build_dir}}/index.html

# Check spec for broken links
validate-spec-links:
  linkchecker {{spec_build_dir}}/index.html

# Sync Vale styles and dictionaries
vale-sync:
  vale sync

# Watch for changes and rebuild automatically
watch:
  watchfiles 'just build' spec/ conformance/
