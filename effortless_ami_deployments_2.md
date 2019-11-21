# Effortless AMI Deployments with Chef Infra and Habitat - Part 2

This is Part 2 of a series. Please make sure and read [Part 1]() before continuing.

## Deploying Habitat

In Part 1 of this series, we generated a new "webserver" cookbook, built a Habitat package with it and then pushed that to the [Habitat Builder](https://bldr.habitat.sh/#/pkgs/uship/webserver/latest). Now, we're going to deploy a Windows server on Amazon Web Services. This server will load our Habitat package when it's created and after it runs then we should have the default IIS site running.

The first thing we need to do is login to the AWS Management Console and go to the EC2 Dashboard:

![EC2 Dashboard picture]()

Click on "Launch instance" which will take us to the wizard for launching a server. 

![Launch instance picture]()

Search or scroll down to the image "Microsoft Windows Server 2012 R2 Base" and click "Select" to go to the next screen.

![Launch instance wizard - Choose AMI]()

Select an instance size for your server. I'll use t2.micro to stay in the AWS free tier.

![Launch instance wizard - Choose Instance Type]()

Click the "Next: Configure Instance Details" button. On the next page, select a VPC or create a new one if you don't have one already then scroll to the bottom and the following to the "User data" under the "Advanced Details" and click "Next: Add Storage"

```
<powershell>
Start-Transcript
# Install Habitat
if ((Get-Command "hab" -ErrorAction SilentlyContinue)) {
    Write-Host "Habitat Installation found"
} else {
    Write-Host "Habitat Installation not found, installing..."
    (New-Object System.Net.WebClient).DownloadString('https://raw.githubusercontent.com/habitat-sh/habitat/master/components/hab/install.ps1') | Out-File install.ps1
    # Install Habitat
    if (Test-Path -Path env:HAB_VERSION) {
        .\install.ps1 -Version $env:HAB_VERSION
    } else {
        .\install.ps1
    }
}

if (!(Test-Path -Path env:HAB_LICENSE)) {
    $env:HAB_LICENSE="accept-no-persist"
}

# Install supervisor and Habitat Windows Service
Write-Host "Installing Habitat Supervisor and Windows Service..."
hab pkg install core/hab-sup
hab pkg install core/windows-service
hab pkg exec core/windows-service install
[System.Environment]::SetEnvironmentVariable("HAB_LICENSE", "accept", [System.EnvironmentVariableTarget]::Machine)

Write-Host "Finished Installing Habitat Supervisor and Windows Service"

Start-Service -Name "Habitat"

Write-Host "Installing webserver package"
C:\ProgramData\Habitat\hab.exe pkg install uship/webserver
Write-Host "webserver package installed"
Write-Host "Loading webserver service"
C:\ProgramData\Habitat\hab.exe svc load uship/webserver
Write-Host "webserver service loaded"
Stop-Transcript
</powershell>
```

![Launch instance wizard - Configure Instance]()

You can leave the default storage size or adjust it as needed and click "Next: Add Tags" to go to the next step. Feel free to add any tags that you'd like. I'm going to set a "Name" tag so I can easily find the server.

![Launch instance wizard - Add Tags]()

On the next step, create a new security group or select an existing one. You'll want one that has port 80 open and also 3389 if you want to be able to remote into it. Click on "Review and Launch" and make sure your settings are good. Click the "Launch" button to create the server and make sure to create or select a keypair before clicking the "Launch Instances" button. Launching the server will take a few minutes but after it's up, grab the password, using the private key that corresponds to the keypair you selected at launch time, and login remotely to the instance.

To make sure that everything worked properly, we'll check a couple of things. First, go to the `C:\Users\Administrator\Documents` directory and open the Powershell transcript.

![Documents directory]()

![Powershell transcript]()

In the transcript, we can see the Habitat installation, starting the Habitat service, and then loading the webserver package. To check that the Chef run completed successfully, open the `Habitat.log` file from the `C:\hab\svc\windows-service\logs` directory. You can see it loading the Habitat supervisor and then running the Chef Client:

```
2019-11-21 19:33:33,806 - Habitat windows service is starting launcher at: C:\hab\pkgs\core\hab-launcher\12605\20191112144934\bin\hab-launch.exe
2019-11-21 19:33:33,816 - Habitat windows service is starting launcher with args: run --no-color
2019-11-21 19:33:34,216 - hab-sup(MR): core/hab-sup (core/hab-sup/0.90.6/20191112145002)
2019-11-21 19:33:34,216 - hab-sup(MR): Supervisor Member-ID efdc426fe81743deac99d168bbda512e
2019-11-21 19:33:34,216 - hab-sup(MR): Starting gossip-listener on 0.0.0.0:9638
2019-11-21 19:33:34,216 - hab-sup(MR): Starting ctl-gateway on 127.0.0.1:9632
2019-11-21 19:33:34,216 - hab-sup(MR): Starting http-gateway on 0.0.0.0:9631
2019-11-21 19:33:35,145 - Logging configuration file 'C:\hab/sup\default\config\log.yml' not found; using default logging configuration
2019-11-21 19:34:41,087 - hab-sup(AG): The uship/webserver service was successfully loaded
2019-11-21 19:34:44,114 - hab-sup(MR): Starting uship/webserver (uship/webserver/0.0.1/20191115133545)
2019-11-21 19:34:44,137 - webserver.default(UCW): Watching user.toml
2019-11-21 19:34:44,153 - webserver.default(HK): Modified hook content in C:\hab\svc\webserver\hooks\run
2019-11-21 19:34:44,154 - webserver.default(SR): Hooks recompiled
2019-11-21 19:34:44,166 - webserver.default(CF): Created configuration file C:\hab\svc\webserver\config\attributes.json
2019-11-21 19:34:44,166 - webserver.default(CF): Created configuration file C:\hab\svc\webserver\config\bootstrap-config.rb
2019-11-21 19:34:44,166 - webserver.default(CF): Created configuration file C:\hab\svc\webserver\config\client-config.rb
2019-11-21 19:34:44,166 - webserver.default(SR): Initializing
2019-11-21 19:34:45,126 - webserver.default(SV): Starting service as user=win-3bdeq9ruckm$, group=<anonymous>
2019-11-21 19:34:56,767 - webserver.default(O): Starting Chef Client, version 14.11.21[0m
2019-11-21 19:35:02,230 - webserver.default(O): Using policy 'webserver' at revision '835107fe240d0a571c9d2fc7450a88e208b0f04c5c5e8cbd3865c3838439d4b9'[0m
2019-11-21 19:35:02,236 - webserver.default(O): resolving cookbooks for run list: ["webserver::default@0.1.0 (b9bf53c)"][0m
2019-11-21 19:35:02,349 - webserver.default(O): Synchronizing Cookbooks:[0m
2019-11-21 19:35:02,535 - webserver.default(O):   - iis (7.2.0)[0m
2019-11-21 19:35:02,573 - webserver.default(O):   - webserver (0.1.0)[0m
2019-11-21 19:35:02,611 - webserver.default(O):   - windows (6.0.1)[0m
2019-11-21 19:35:02,611 - webserver.default(O): Installing Cookbook Gems:[0m
2019-11-21 19:35:02,639 - webserver.default(O): Compiling Cookbooks...[0m
2019-11-21 19:35:02,740 - webserver.default(O): Converging 2 resources[0m
2019-11-21 19:35:02,740 - webserver.default(O): Recipe: iis::default[0m
2019-11-21 19:35:02,763 - webserver.default(O):   * iis_install[install IIS] action install
2019-11-21 19:35:02,764 - webserver.default(O):     * windows_feature[IIS-WebServerRole] action install
2019-11-21 19:35:49,670 - webserver.default(O):       * windows_feature_dism[IIS-WebServerRole] action install
2019-11-21 19:35:49,670 - webserver.default(O):         [32m- install Windows feature iis-webserverrole[0m
2019-11-21 19:35:49,670 - webserver.default(O): [0m    
2019-11-21 19:35:49,670 - webserver.default(O): [0m  
2019-11-21 19:35:51,202 - webserver.default(O): [0m  * windows_service[iis] action enable (up to date)
2019-11-21 19:35:51,383 - webserver.default(O):   * windows_service[iis] action start (up to date)
2019-11-21 19:35:51,427 - webserver.default(O): [0m
2019-11-21 19:35:51,427 - webserver.default(O): Running handlers:[0m
2019-11-21 19:35:51,427 - webserver.default(O): Running handlers complete
2019-11-21 19:35:51,433 - webserver.default(O): [0mChef Client finished, 3/5 resources updated in 54 seconds[0m
```

We can see that Chef ran the `iis::default` recipe to install IIS and start the service. Let's go to the IP address of the instance and you can see the default IIS site:

![IIS Default Site]()

At this point, we've shown how we can leverage Habitat and Powershell user data to bring up a server and configure it without having to fully [bootstrap](https://docs.chef.io/install_bootstrap.html) it. In Part 3 of this series, we'll look at how we can utilize the Parameter Store in AWS Systems Manager to handle dynamic configuration that was traditionally kept in [Chef Vault](https://docs.chef.io/chef_vault.html) or [Data Bags](https://docs.chef.io/data_bags.html).
