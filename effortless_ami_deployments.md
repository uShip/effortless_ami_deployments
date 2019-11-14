# Effortless AMI Deployments with Chef Infra and Habitat - Part 1

## Background

At uShip, we've been moving to an AMI deployment strategy for standing up web servers that houses our main application. We made the decision as part of a larger strategy to ensure our environments (dev, qa, prod, etc.) were as similar as possible. We figured that if we could build a single AMI that is deployed to every environment, that would be a huge step in accomplishing environment parity. While the process has mostly been straight-forward, we have run into a problem and the new [Effortless Infrastructure Pattern](https://www.chef.io/products/effortless-infrastructure/) from Chef provided an elegant solution.

## The Problem

[Chef Infra](https://www.chef.io/products/chef-infra/) is a great way of managing configuration for servers. One of the biggest reasons that we reached for Chef versus something else is the Windows support. While other options have gotten better, Chef had the support back in 2015 when we were evaluating configuration management solutions. Chef's client/server model allowed us to get visibilty into our fleet. However, that visibility comes at a cost.

The cost has to do with bootstrapping nodes into the Chef Server. Traditionally, this process works well as you'd usually have long-lived nodes and if you wanted to remove one, you could do that manually using the `chef-server-ctl`. With our AMI deployment strategy, we were creating and destroying nodes every deployment so we were left with many missing nodes and no easy way of cleaning them up. Before we get into the effortless pattern, let's look at the traditional way of bootstrapping a node.

## Bootstrapping Chef Nodes

In Chef, bootstrapping is the process that installs the Chef Infra Client and sets up the node to communicate with the Chef Server. This can either be done using the `knife bootstrap` command from your workstation or, in the case of AWS, with a user data script. Here's an example of what we were using for an unattended bootstrap:

```powershell
Write-Output "Pull the encrypted_data_bag_secret key from S3"
& "C:/Program Files/Amazon/AWSCLI/bin/aws.exe" s3 cp s3://<my-super-real-s3-bucket>/default-validator.pem C:/chef/
& "C:/Program Files/Amazon/AWSCLI/bin/aws.exe" s3 cp s3://<my-super-real-s3-bucket>/encrypted_data_bag_secret C:/chef/encrypted_data_bag_secret

Write-Output "Create first-boot.json for Chef bootstrap into $environment policy_group"
$firstBoot = @{"policy_name" = "web"; "policy_group" = "$environment" }
Set-Content -Path C:/chef/first-boot.json -Value ($firstboot | ConvertTo-Json -Depth 10)

Write-Output "Create client.rb file for Chef using a dynamically-generated node name"
$nodeName = "$(hostname)-{0}" -f ( -join ((65..90) + (97..122) | Get-Random -Count 4 | % { [char]$_ }))

$clientrb = @"
 chef_server_url 'https://chef-server.example.com/organizations/default'
 validation_client_name 'default-validator'
 validation_key 'C:/chef/default-validator.pem'
 node_name '{0}'
"@ -f $nodeName
Set-Content -Path C:/chef/client.rb -Value $clientrb

Write-Output "Run Chef client first time"
C:/opscode/chef/bin/chef-client.bat -j C:/chef/first-boot.json
```

I'd like to note that we were originally using [Chef Vault](https://docs.chef.io/chef_vault.html) to store secrets but there doesn't appear to be a way for a node to bootstrap itself and then give itself permissions to a vault item and so we're using [encrypted data bags](https://docs.chef.io/data_bags.html#encrypt-a-data-bag-item) here.

Assuming that you've set up your S3 bucket policy and EC2 instance role, this solution works well to bring up instances. But, as mentioned earlier, if you boot up four new servers in each environment every time you deploy, you'll have an increasing number of missing nodes. There is a [Lambda](https://github.com/awslabs/lambda-chef-node-cleanup) out on the interwebs for cleaning up nodes in the Chef Server, but this is kinda of a pain to do and only addresses the Chef Server; it does nothing for the ones in [Chef Automate](https://www.chef.io/products/automate/).

## Effortless Infrastructure

If you missed the session from ChefConf 2019, there's an excellent talk by David Echols about [what effortless config is](https://chefconf.chef.io/conf-resources/effortless-config-101/). Essentially, the effortless pattern is a way to build and run your cookbooks as a single, deployable package. It accomplishes this using [Habitat](https://habitat.sh), [Policyfiles](https://docs.chef.io/policyfile.html), and [Chef Solo](https://docs.chef.io/chef_solo.html). Before reading further, I urge you to check out that video and the track on [Learn Chef Rally](https://learn.chef.io/tracks/habitat-build#/).

### Prerequisites

- [Chef Workstation](https://www.chef.sh/about/chef-workstation/)
- [Habitat](https://www.habitat.sh/)

### Generate a Cookbook

The first thing we need to do is generate a new cookbook. I'm going to deploy a cookbook that sets up IIS on a Windows server but the concepts should be similar if you're deploying Linux servers.

```shell
PS C:\Users\uship\Projects> chef generate cookbook webserver
Generating cookbook webserver
- Ensuring correct cookbook content
- Committing cookbook files to git

Your cookbook is ready. To setup the pipeline, type `cd webserver`, then run `delivery init`
```

Let's check out the content of the `webserver` cookbook:

```shell
PS C:\Users\uship\Projects> cd webserver
PS C:\Users\uship\Projects\webserver> tree
.
├── CHANGELOG.md
├── LICENSE
├── Policyfile.rb
├── README.md
├── chefignore
├── kitchen.yml
├── metadata.rb
├── recipes
│   └── default.rb
├── spec
│   ├── spec_helper.rb
│   └── unit
│       └── recipes
│           └── default_spec.rb
└── test
    └── integration
        └── default
            └── default_test.rb

7 directories, 11 files
```

To set up IIS, we're going to leverage the [iis cookbook](https://supermarket.chef.io/cookbooks/iis). Add the following to the `metadata.rb` file:

```ruby
name 'webserver'
maintainer 'The Authors'
.
.
.
# source_url 'https://github.com/<insert_org_here>/webserver'

depends 'iis', '~> 7.2.0'
```

We'll need to go ahead and install the dependencies. For this, we'll leverage Policyfiles. If you are unfamiliar, they're basically what replaces [Berkshelf](https://docs.chef.io/berkshelf.html) and environments/roles. Check out the [documentation](https://docs.chef.io/policyfile.html) but you should just need to run the following:

```shell
PS C:\Users\uship\Projects\webserver> chef install
Building policy webserver
Expanded run list: recipe[webserver::default]
Caching Cookbooks...
Installing webserver >= 0.0.0 from path
Installing iis       7.2.0
Installing windows   6.0.1

Lockfile written to /Users/uship/Documents/effortless_ami_deployments/webserver/Policyfile.lock.json
Policy revision id: c2746cac28e13e1dae4fa99f4b9f9d56e5b7bf11894f1cce1e8940a2f4de42c3
```

Now that we have our dependencies installed, let's update the Chef recipe to install IIS.

```ruby
#
# Cookbook:: webserver
# Recipe:: default
#
# Copyright:: 2019, The Authors, All Rights Reserved.

include_recipe 'iis'
```

This will install IIS on the server and enable the W3SVC service. At this point, if you boot up a [Test Kitchen](https://docs.chef.io/kitchen.html) instance to test and then browse to the IP address, you should see the default Internet Information Services page.

### Package the Cookbook

As I said earlier, the effortless infrastructure pattern leverages [Habitat](https://habitat.sh) to package and run your Chef cookbook like an application. To package this up, we'll need to habitatize our application and create a basic structure. Note that this is going to be deployed and run on a Windows server so it needs to be built on a Windows box to work properly. If you're working on Mac or Linux, the concepts are the same but you'd use Bash instead of Powershell for writing your plan. Again, I'll defer to the [Habitat documentation](https://www.habitat.sh/docs/developing-packages/#write-plans) for the specifics.

From the root of your cookbook directory, initialize the Habitat plan, using your [origin](https://www.habitat.sh/docs/using-builder/#create-an-origin-on-builder):

```shell
PS C:\Users\uship\Projects\webserver> hab plan init -o uship
» Constructing a cozy habitat for your app...

Ω Creating file: habitat/plan.ps1
  `plan.sh` is the foundation of your new habitat. It contains metadata,
  dependencies, and tasks.

Ω Creating file: habitat/default.toml
  `default.toml` contains default values for `cfg` prefixed variables.

Ω Creating file: habitat/README.md
  `README.md` contains a basic README document which you should update.

Ω Creating directory: habitat/config/
  `/config/` contains configuration files for your app.

Ω Creating directory: habitat/hooks/
  `/hooks/` contains automation hooks into your habitat.

  For more information on any of the files:
  https://www.habitat.sh/docs/reference/plan-syntax/

→ Using existing file: habitat/../.gitignore (1 lines appended)
≡ An abode for your code is initialized!
```

For the effortless infrastructure, we'll lean on the [Habita Scaffolding](https://www.habitat.sh/docs/glossary/#scaffolding) provided by the Habitat core team. You can see what the scaffolding is doing by looking in the [repository](https://github.com/chef/effortless/tree/master/scaffolding-chef-infra), but all we need to do is update the `habitat/plan.ps1` file:

```powershell
# This is the name of our Habitat package
$pkg_name="webserver"

# Update this with your origin
$pkg_origin="uship"

# Package version. Typically follomws Semantic Versioning
$pkg_version="0.0.1"

# Update this per your preferences
$pkg_maintainer="uShip, Inc. <devops@uship.com>"

# We need these dependencies for our application to run
$pkg_deps=@(
  "core/cacerts"
  "stuartpreston/chef-client" # https://github.com/habitat-sh/habitat/issues/6671
)

# Use the scaffolding-chef-infra scaffolding
$pkg_scaffolding="chef/scaffolding-chef-infra"

# Name of our Policyfile
$scaffold_policy_name="Policyfile"

# Location of the Policyfile. In this case, habitat/../Policyfile.rb
$scaffold_policyfile_path="$PLAN_CONTEXT/../"
```

The last thing we need to do before we can build our Habitat package is update the configuration for the Chef Client that will be running. Habitat's uses [Toml](https://github.com/toml-lang/toml) for configuration and the default config is in `habitat/default.toml`:

```toml
# Use this file to templatize your application's native configuration files.
# See the docs at https://www.habitat.sh/docs/create-packages-configure/.
# You can safely delete this file if you don't need it.

# Run the Chef Client every 5 minutes
interval = 300

# Offset the Chef Client runs by 30 seconds
splay = 30

# No offset for the first run
splay_first_run = 0

# Wait for Chef Client run lock file to be deleted
run_lock_timeout = 300
```

Go ahead and remove the `habitat/config` and `habitat/hooks` directories as these aren't needed and tend to cause errors with the build:

```shell
PS C:\Users\uship\Projects\webserver> rmdir habitat/config
PS C:\Users\uship\Projects\webserver> rmdir habitat/hooks
```

To build our Habitat package, we'll enter the Habitat studio. The studio is a clean room which only packages up the dependencies that have been specified and nothing else. 

```shell
PS C:\Users\uship\Projects\webserver> hab studio enter
WARNING: Using a local Studio. To use a Docker studio, use the -D argument.
   hab-studio: Creating Studio at C:\hab\studios\Users--uship--Projects--webserver
» Importing origin key from standard input
≡ Imported public origin key uship-20190919164651.
» Importing origin key from standard input
≡ Imported secret origin key uship-20190919164651.
** The Habitat Supervisor has been started in the background.
** Use 'hab svc start' and 'hab svc stop' to start and stop services.
** Use the 'Get-SupervisorLog' command to stream the Supervisor log.
** Use the 'Stop-Supervisor' to terminate the Supervisor.

   hab-studio: Entering Studio at C:\hab\studios\Users--uship--Projects--webserver
[HAB-STUDIO] Habitat:\src>
```

Inside the studio, we'll run `build` which will us the default location of the plan file in `habitat/plan.ps1`:

```shell
[HAB-STUDIO] Habitat:\src> build
   : Loading C:\hab\studios\Users--uship--Projects--webserver\src\habitat\plan.ps1
   webserver: Plan loaded
   webserver: Validating plan metadata
   webserver: hab-plan-build.ps1 setup
   webserver: Using HAB_BIN=C:\hab\pkgs\core\hab-studio\0.83.0\20190712234514\bin\hab\hab.exe for installs, signing, and hashing
   webserver: Resolving scaffolding dependencies
» Installing chef/scaffolding-chef-infra
⌂ Determining latest version of chef/scaffolding-chef-infra in the 'stable' channel
→ Using chef/scaffolding-chef-infra/0.16.0/20191028151207
≡ Install of chef/scaffolding-chef-infra/0.16.0/20191028151207 complete with 0 new packages installed.
   webserver: Resolved scaffolding dependency 'chef/scaffolding-chef-infra' to C:\hab\studios\Users--uship--Projects--webserver\hab\pkgs\chef\scaffolding-chef-infra\0.16.0\20191028151207
   webserver: Loading Scaffolding C:\hab\studios\Users--uship--Projects--webserver\hab\pkgs\chef\scaffolding-chef-infra\0.16.0\20191028151207/lib/scaffolding.ps1
» Installing chef/scaffolding-chef-infra
⌂ Determining latest version of chef/scaffolding-chef-infra in the 'stable' channel
→ Using chef/scaffolding-chef-infra/0.16.0/20191028151207
≡ Install of chef/scaffolding-chef-infra/0.16.0/20191028151207 complete with 0 new packages installed.
   webserver: Resolved build dependency 'chef/scaffolding-chef-infra' to C:\hab\studios\Users--uship--Projects--webserver\hab\pkgs\chef\scaffolding-chef-infra\0.16.0\20191028151207
» Installing core/chef-dk/2.5.3/20180416182816
→ Using core/chef-dk/2.5.3/20180416182816
.
.
.
   webserver: Preparing to build
   webserver: Building
Building policy webserver
Expanded run list: recipe[webserver::default]
Caching Cookbooks...
Installing webserver >= 0.0.0 from path
Using      iis       7.2.0
Using      windows   6.0.1

Lockfile written to C:/hab/studios/Users--uship--Projects--webserver/src/Policyfile.lock.json
Policy revision id: f8a3f2d55e079328c164d2c0250854348cdb7900e89c4c8e9cbe155825d7635b
   webserver: Installing
Exported policy 'webserver' to C:\hab\studios\Users--uship--Projects--webserver\hab\pkgs\uship\webserver\0.0.1\20191114064617

To converge this system with the exported policy, run:
  cd C:\hab\studios\Users--uship--Projects--webserver\hab\pkgs\uship\webserver\0.0.1\20191114064617
  chef-client -z


    Directory: C:\hab\studios\Users--uship--Projects--webserver\hab\pkgs\uship\webserver\0.0.1\20191114064617

Mode                LastWriteTime         Length Name
----                -------------         ------ ----
d-----        11/14/2019  6:47 AM                config
   webserver: Writing configuration
   webserver: Writing default.toml
d-----        11/14/2019  6:47 AM                hooks
   webserver: Creating manifest
   webserver: Building package metadata
   webserver: Generating package artifact
» Signing C:\hab\studios\Users--uship--Projects--webserver\hab\cache\artifacts\.uship-webserver-0.0.1-20191114064617-x86_64-windows.tar.xz
→ Signing C:\hab\studios\Users--uship--Projects--webserver\hab\cache\artifacts\.uship-webserver-0.0.1-20191114064617-x86_64-windows.tar.xz with uship-20190919164651 to create C:\hab\studios\Users--uship--Projects--webserver\hab\cache\artifacts\uship-webserver-0.0.1-20191114064617-x86_64-windows.hart
≡ Signed artifact C:\hab\studios\Users--uship--Projects--webserver\hab\cache\artifacts\uship-webserver-0.0.1-20191114064617-x86_64-windows.hart.
   webserver: hab-plan-build.ps1 cleanup
   webserver:
   webserver: Source Cache: C:\hab\studios\Users--uship--Projects--webserver\hab\cache\src\webserver-0.0.1
   webserver: Installed Path: C:\hab\studios\Users--uship--Projects--webserver\hab\pkgs\uship\webserver\0.0.1\20191114064617
   webserver: Artifact: C:\hab\studios\Users--uship--Projects--webserver\src\results\uship-webserver-0.0.1-20191114064617-x86_64-windows.hart
   webserver: Build Report: C:\hab\studios\Users--uship--Projects--webserver\src\results\last_build.ps1
   webserver: SHA256 Checksum:
   webserver: Blake2b Checksum:
   webserver:
   webserver: I love it when a plan.ps1 comes together.
   webserver:
```

If everything is successful, the newly-built package will be in the `results` directory. Let's go ahead and push it to the [Habitat Bldr Service](https://bldr.habitat.sh/). We can use the `results/last_build.ps1` file to set variables so we don't need to specify the full path to the artifact. Note that you'll need to make sure your [auth token](https://www.habitat.sh/docs/using-builder/#builder-token) is set up.

```shell
PS C:\Users\uship\Projects\webserver\results> . .\last_build.ps1
PS C:\Users\uship\Projects\webserver\results> hab pkg upload $pkg_artifact
    79 B / 79 B | [=====================================================================================================================================================================================] 100.00 % 654 B/s
→ Using existing public origin key uship-20190919164651.pub
→ Using existing core/cacerts/2019.08.28/20190829172945
→ Using existing stuartpreston/chef-client/14.11.21/20190328012639
↑ Uploading uship-webserver-0.0.1-20191114064617-x86_64-windows.hart
    70.89 KB / 70.89 KB | [===========================================================================================================================================================================] 100.00 % 1.45 MB/s
√ Uploaded uship/webserver/0.0.1/20191114064617
≡ Upload of uship/webserver/0.0.1/20191114064617 complete.
```

You should now have a public "webserver" package available in the "unstable" channel of your Habitat origin. In the next part of this blog post series, we'll build an AMI and deploy our new package to a server using that AMI. If you want to see the code for this, it's available at [https://github.com/uShip/effortless_ami_deployments](https://github.com/uShip/effortless_ami_deployments).
