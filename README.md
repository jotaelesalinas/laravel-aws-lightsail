# Laravel in AWS Lightsail with testing, production and no downtime

**Important**: This is work in progress.

What you need:

1. A Laravel application in a git reporitory
2. An AWS Lightsail instance
3. A web domain

We assume that you know how to use git with your Laravel application
and how to point your web domain to an IP address.

We will focus on how to create the Lightsail instance, how to configure a testing
and production website inside and how to automate the updates of the application.

## Creating the Lightsail instance

1. Pick the region closest to your potential visitors
2. Choose platform “Linux/Unix"
3. Select “Ubuntu 18.04 LTS” or any newer LTS when available
4. Choose one plan according to the usage that you expect
5. Give it a nice name
6. Click “Create instance"

### Getting a static IP address

1. Go to “Networking”
2. Click "Create a static IP"
3. Assign it to the instance you just created

Write down the IP address. You will need it to configure the DNS records and to connect via SSH to your instance.

### Connecting via SSH

In the “Instances” tab of Lightsail, click the instance that you just created.

You will find yourself in the “Connect” section.

You can always click “Connect using SSH” from any computer if you need to troubleshoot or do some urgent works.

Most of the times, you will connect via SSH from your terminal or from your file transfer tool (e.g. WinSCP or Cyberduck). For this, you will need three things:

1. The public IP address of the instance
2. The username
3. The private key

The IP and the username are quite visible in the website, inside a box. Write them down.

The SSH private key is needed because there is no possibility of connecting with the traditional username and password. You have to download to your computer a special file (that contains basically a very long password, called private key) and tell your SSH program to use it.

In order to download the private key, scroll down and click “Account page” in the last paragraph. You will land in the “Manage your SSH keys” section of your account page and from there you have to download the SSH key for the instance that you have created.

Keep it in a safe place.

To connect to the server in the terminal:

```bash
ssh -I <path to LightsailDefaultKey-zone.pem> ubuntu@<IP address>
```

## 1st time setup

Ubuntu 18.04 comes with git. Anyway, you can make sure by typing:

```bash
git --version
```

If git is not present in your system, type:

```bash
sudo apt install git
```

Now, clone this repo:

```bash
git clone https://github.com/jotaelesalinas/laravel-aws-lightsail.git
```

Change to laravel-aws-lightsail:

```bash
cd laravel-aws-lightsail
```

The first thing that you will have to do is copy `config.ini-example` as `config.ini`:

```bash
cp config.ini-example config.ini
```

Open `config.ini` in your favorite cli editor -if there is such a thing- and enter the data according to your needs:

```bash
nano config.ini
```

Default contents are:

```
# list of the environments, between parenthesis, with double quotes, separated by spaces
# the first one will be marked as default in the nginx configuration
environments=( "production" "testing" )

# your domain
domain=example.com

# one git_branch_* per environment
git_branch_production=master
git_branch_testing=testing

# the remote git site
git_site=gitlab.com

# your remote site username
git_user=myusername

# your remote site repository
git_repo=example.com-web
```

You really need to have your DNS configured correctly.

Once you have the config file ready, give exution permission to `first-run.sh` and run it:

```bash
chmod +x first-run.sh
./first-run.sh
```

I suggest that you have a look at the file before, in order to see what it is going to do.

You might need different software or extra extensions, e.g. PostgreSQL instead of MySQL or php-gd.

Stick to Nginx, or the installation will not work.

This script will luckily install Nginx with PHP 7.3 and MySQL, on one side, and configure the environments
that you indicated in `config.ini`'s `environments` variable, on the other side.

You will be left in your home directory, and you will find this:

1. The file `config.ini`
2. The file `update.sh`, that you will use to update your Laravel application
3. One directory per environment, e.g. `production`, `testing`

Each one of the directories has a subdirectory named `public`, mimicking Laravel installations, with an `index.html` file.

Now you should be able to navigate to www.example.com and testing.example.com and see the default message.

What _you_ still have to do:

- nginx config file for default environment: change subdomain to www and probably also with no domain
- create .env in each environment's directory, with different keys

## Update application

Log in to your Lightsail instance.

Run:

```bash
./update.sh <environment>
```

You should also familiarize yourself with this file. If something goes wrong it can break your website. Automation is good, but _we_ have to be always under control.

## To do

- [ ] Delete failed installations, rolling back migrations if needed
- [ ] Create `rollback.sh`
- [ ] Create a hook in gitlab/github/etc that calls _somehow_ `update.sh <environment>` when the corresponding branches are updated.
- [ ] Add some screenshots to the tutorial
- [ ] Create a command that "promotes" (that is, merges) testing into master.
- [ ] Slack notifications
- [ ] Slack commands, e.g. for promoting, for rolling back
- [ ] Add an option in `config.ini` to enable maintenance mode in one environment. This way, the admins check that everything is ok while the users see the maintenance message.
- [ ] Add an option to tell how many older instances are kept
- [ ] Add https://letsencrypt.org/
