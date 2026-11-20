# shellcheck shell=bash
# Static checks on action.yml that GitHub only reports at run time (or at
# Marketplace publish time), so mistakes surface before a release.

check_action_metadata() {
  # shellcheck disable=SC2016 # Ruby source, not shell
  ruby -ryaml -e '
    action_path, root = ARGV
    raw = File.read(action_path)
    action = YAML.safe_load(raw)
    errors = []

    # https://docs.github.com/actions/sharing-automations/creating-actions/metadata-syntax-for-github-actions#branding
    colors = %w[white black yellow blue green orange red purple gray-dark]
    errors << "name missing" if action["name"].to_s.empty?
    errors << "description missing" if action["description"].to_s.empty?
    errors << "description must be < 125 chars for the Marketplace" if action["description"].to_s.length >= 125
    errors << "author missing" if action["author"].to_s.empty?
    errors << "branding.color invalid" unless colors.include?(action.dig("branding", "color"))
    errors << "branding.icon missing" if action.dig("branding", "icon").to_s.empty?
    errors << "runs.using must be composite" unless action.dig("runs", "using") == "composite"

    inputs = (action["inputs"] || {}).keys
    raw.scan(/inputs\.([A-Za-z0-9_-]+)/).flatten.uniq.each do |name|
      errors << "undeclared input referenced: #{name}" unless inputs.include?(name)
    end
    (action["inputs"] || {}).each do |name, spec|
      errors << "input #{name} has no description" if spec["description"].to_s.empty?
    end

    steps = action.dig("runs", "steps") || []
    ids = steps.map { |s| s["id"] }.compact
    raw.scan(/steps\.([A-Za-z0-9_-]+)\.outputs/).flatten.uniq.each do |id|
      errors << "unknown step id referenced: #{id}" unless ids.include?(id)
    end
    steps.each do |step|
      label = step["name"] || step["id"]
      next unless step["run"]
      errors << "step #{label} has no shell" unless step["shell"]
      errors << "step #{label} interpolates ${{ }} inside run (script injection); use env" if step["run"].include?("${{")
      step["run"].scan(%r{\$GITHUB_ACTION_PATH/(\S+\.sh)}).flatten.each do |script|
        errors << "step #{label} runs missing script #{script}" unless File.file?(File.join(root, script))
      end
    end

    (action["outputs"] || {}).each do |name, spec|
      errors << "output #{name} has no description" if spec["description"].to_s.empty?
      errors << "output #{name} has no value" if spec["value"].to_s.empty?
    end

    if errors.empty?
      exit 0
    else
      warn errors.join("\n")
      exit 1
    end
  ' "$1" "$ROOT_DIR"
}

test_action_metadata_is_valid_for_marketplace() {
  check_action_metadata "$ROOT_DIR/action.yml"
}

test_action_metadata_check_detects_script_injection() {
  cat >"$TEST_TMP/action.yml" <<'EOF'
name: Example
description: Example
author: Someone
branding: { icon: upload-cloud, color: green }
inputs:
  scheme: { description: Scheme }
runs:
  using: composite
  steps:
    - run: echo "${{ inputs.scheme }}"
      shell: bash
EOF
  assert_fails check_action_metadata "$TEST_TMP/action.yml"
}

# The input build number is only a request: projects whose Info.plist does not
# use $(CURRENT_PROJECT_VERSION) keep their own, so report what was archived.
test_action_build_number_output_comes_from_the_archive() {
  local value
  # shellcheck disable=SC2016 # Ruby source, not shell
  value="$(ruby -ryaml -e 'puts YAML.safe_load(File.read(ARGV[0])).dig("outputs", "buildNumber", "value")' "$ROOT_DIR/action.yml")"
  # shellcheck disable=SC2016 # literal GitHub expression
  assert_eq '${{ steps.archive.outputs.buildNumber }}' "$value"
}
