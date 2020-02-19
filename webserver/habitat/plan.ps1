# This is the name of our Habitat package
$pkg_name="webserver"

# Update this with your origin
$pkg_origin="uship"

# Package version. Typically follows Semantic Versioning
$pkg_version="0.0.2"

# Update this per your preferences
$pkg_maintainer="uShip, Inc. <devops@uship.com>"

# Use the scaffolding-chef-infra scaffolding
$pkg_scaffolding="chef/scaffolding-chef-infra"

# Name of our Policyfile
$scaffold_policy_name="Policyfile"

# Location of the Policyfile. In this case, habitat/../Policyfile.rb
$scaffold_policyfile_path="$PLAN_CONTEXT/../"