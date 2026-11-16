# Terraform + Ansible: Automated EC2 Node.js Deployment

Provision an AWS EC2 server with **Terraform** and deploy a Node.js application onto it with **Ansible**, all from one command. Terraform creates the infrastructure, then automatically generates an Ansible inventory and runs the playbook against the new instance.

```bash
terraform init
terraform apply
```

---

## Table of Contents

- [How It Works](#how-it-works)
- [What Gets Created](#what-gets-created)
- [Requirements](#requirements)
- [Project Structure](#project-structure)
- [Quick Start](#quick-start)
- [Configuration](#configuration)
- [What the Playbook Does](#what-the-playbook-does)
- [Verifying the Deployment](#verifying-the-deployment)
- [Re-running the Deployment](#re-running-the-deployment)
- [Cleaning Up](#cleaning-up)
- [Troubleshooting](#troubleshooting)
- [Security Notes](#security-notes)
- [Contributing](#contributing)

---

## How It Works

```
terraform apply
      │
      ├─► 1. Create security group  (SSH 22, app 3000)
      │
      ├─► 2. Launch EC2 instance    (t2.micro, ap-south-1)
      │
      └─► 3. local-exec provisioner
              ├─ wait 30s for SSH to come up
              ├─ write inventory.ini with the instance's public IP
              └─ run ansible-playbook playbook.yml
                      │
                      └─► Install Node.js 22 → clone app → npm install
                          → create systemd service → start on port 3000
```

Because the Ansible run is attached to the instance as a `local-exec` provisioner, you never write an inventory by hand or copy the IP address anywhere.

---

## What Gets Created

| Resource | Details |
|---|---|
| `aws_security_group.nodejs-app-sg` | Inbound TCP 22 (SSH) and TCP 3000 (app) from anywhere; all outbound allowed |
| `aws_instance.nodejs-deployment` | `t2.micro` instance named `nodejs-app-deploy`, launched with the `devops-key` key pair in the default VPC |
| `inventory.ini` (local file) | Generated at apply time with the instance's public IP |

By default the playbook deploys [`rat9615/simple-nodejs-app`](https://github.com/rat9615/simple-nodejs-app) with Node.js 22 as a `systemd` service on port 3000.

---

## Requirements

### Tools on your machine

| Tool | Version | Notes |
|---|---|---|
| [Terraform](https://developer.hashicorp.com/terraform/install) | `>= 1.0.0` | AWS provider `~> 5.0` (lock file pins `5.100.0`) |
| [Ansible](https://docs.ansible.com/ansible/latest/installation_guide/) | recent | Must be on your `PATH`, since Terraform calls `ansible-playbook` |
| `community.general` collection | | Provides the `npm` module. Included in the full `ansible` package; with `ansible-core` only, run `ansible-galaxy collection install community.general` |
| Linux, macOS, or WSL | | The provisioner uses a shell script with `echo`/`sleep`, so native Windows shells won't work |

### AWS prerequisites

- An AWS account with credentials configured locally (`aws configure`, or the `AWS_ACCESS_KEY_ID` / `AWS_SECRET_ACCESS_KEY` environment variables) and permission to create EC2 instances and security groups
- An **EC2 key pair named `devops-key`** in the `ap-south-1` (Mumbai) region
- The private key saved as **`devops-key.pem` in the project root**, with safe permissions:

  ```bash
  chmod 400 devops-key.pem
  ```
- A **default VPC** in the region (the instance doesn't specify a subnet)
- An Ubuntu AMI. The playbook uses `apt` and connects as the `ubuntu` user, so the AMI configured in `main.tf` must be Ubuntu and available in `ap-south-1` (AMI IDs are region-specific)

---

## Project Structure

```
terraform-ansible-ec2-automated-deployment/
├── main.tf               # Security group, EC2 instance, and Ansible provisioner
├── provider.tf           # Terraform + AWS provider configuration (region)
├── playbook.yml          # Ansible playbook that deploys the Node.js app
├── .terraform.lock.hcl   # Provider version lock file
├── .gitignore            # Keeps state, keys, and generated inventory out of git
└── README.md
```

Files created locally while you work (all git-ignored): `.terraform/`, `terraform.tfstate*`, `inventory.ini`, and your `*.pem` key.

---

## Quick Start

### 1. Clone the repository

```bash
git clone https://github.com/ksajeb/terraform-ansible-ec2-automated-deployment.git
cd terraform-ansible-ec2-automated-deployment
```

### 2. Add your SSH key

Place your private key in the project root as `devops-key.pem`:

```bash
cp /path/to/devops-key.pem .
chmod 400 devops-key.pem
```

### 3. Check your AWS credentials

```bash
aws sts get-caller-identity
```

### 4. Initialize Terraform

```bash
terraform init
```

### 5. Review the plan

```bash
terraform plan
```

### 6. Deploy

```bash
terraform apply
```

Type `yes` when prompted. Terraform creates the resources, waits 30 seconds for SSH, then runs the Ansible playbook. The run ends with:

```
SUCCESS: Node.js application deployment completed!
```

### 7. Open the app

Find the instance's public IP in the AWS console, in the generated `inventory.ini`, or with:

```bash
terraform state show aws_instance.nodejs-deployment | grep public_ip
```

Then visit:

```
http://<public-ip>:3000
```

---

## Configuration

This project has no Terraform input variables; configuration is edited directly in the files below.

### Infrastructure (`main.tf` and `provider.tf`)

| Setting | Current value | File |
|---|---|---|
| AWS region | `ap-south-1` | `provider.tf` |
| AMI | `ami-0c7632fb77f35db43` | `main.tf` |
| Instance type | `t2.micro` | `main.tf` |
| Key pair name | `devops-key` | `main.tf` |
| Private key file | `devops-key.pem` | `main.tf` (provisioner) |
| SSH user | `ubuntu` | `main.tf` (provisioner) |
| App port | `3000` | `main.tf` (security group) and `playbook.yml` |

When changing the region, also change the AMI (IDs differ per region) and make sure the key pair exists there.

### Application (`playbook.yml`)

| Variable | Default | Description |
|---|---|---|
| `github_repo` | `https://github.com/rat9615/simple-nodejs-app.git` | Git repository of the app to deploy |
| `app_dir` | `/node_app` | Directory on the server where the app is cloned |
| `nodejs_version` | `"22"` | Node.js major version installed from NodeSource |

To deploy your own app, set `github_repo` to your repository. It needs a `package.json` at the repo root, a `start` script, and should read its port from `process.env.PORT`.

---

## What the Playbook Does

| # | Task | Purpose |
|---|---|---|
| 1 | Installing Git And Curl | Installs `git`, `curl`, and `ca-certificates` |
| 2 | Configure Node.js repository | Runs the NodeSource setup script for the chosen version (skipped if already configured) |
| 3 | Install Node.js and npm | Installs the `nodejs` package |
| 4 | Create application directory | Creates `app_dir` |
| 5 | Clone application repository | Clones or updates the app (`force: yes` discards local changes) |
| 6 | Install application dependencies | Runs `npm install` |
| 7 | Verify Node.js installation | Runs `node --version` |
| 8 | Create systemd service | Writes `/etc/systemd/system/node-app.service` (runs `npm start` as `ubuntu` with `PORT=3000`) |
| 9 | Start and enable service | Starts `node-app` and enables it on boot |
| 10 | Display success message | Prints the completion message |

A handler restarts the service whenever the unit file changes.

---

## Verifying the Deployment

SSH in using the generated inventory values:

```bash
ssh -i devops-key.pem ubuntu@<public-ip>
```

Then check:

```bash
node --version                                  # Node.js installed
sudo systemctl status node-app                  # service running
sudo journalctl -u node-app -n 50 --no-pager    # recent logs
curl http://localhost:3000                      # app responding
```

---

## Re-running the Deployment

The provisioner runs **only when the instance is created**, so running `terraform apply` again on an existing instance won't re-run Ansible. To redeploy or update the app on the existing server, run the playbook directly using the generated inventory:

```bash
ANSIBLE_HOST_KEY_CHECKING=False ansible-playbook -i inventory.ini playbook.yml
```

The service is only restarted when its unit file changes, so after pulling new app code, restart it on the server with `sudo systemctl restart node-app`.

If the playbook **fails during `terraform apply`**, Terraform marks the instance as *tainted* and will replace it on the next apply. To retry without recreating the server, fix the problem and run the `ansible-playbook` command above instead.

---

## Cleaning Up

Destroy everything Terraform created to stop incurring AWS charges:

```bash
terraform destroy
```

You can then delete the local `inventory.ini` file.

---

## Troubleshooting

**`UNREACHABLE` or SSH timeout during apply**
The instance may need longer than 30 seconds to boot. Re-run the playbook manually (see above). Also confirm the security group allows port 22 and that `devops-key.pem` is in the project root.

**`Permission denied (publickey)`**
The key file doesn't match the `devops-key` key pair, or its permissions are too open. Run `chmod 400 devops-key.pem`.

**`InvalidKeyPair.NotFound`**
No key pair named `devops-key` exists in `ap-south-1`. Create it in the EC2 console or change `key_name` in `main.tf`.

**`InvalidAMIID.NotFound` or architecture/region errors**
The AMI isn't available in your region. Replace it with an Ubuntu AMI for your region.

**`apt` module fails / no package manager found**
The AMI isn't Ubuntu/Debian. Use an Ubuntu AMI.

**`ansible-playbook: command not found`**
Install Ansible on the machine running Terraform.

**`couldn't resolve module/action 'npm'`**
Run `ansible-galaxy collection install community.general`.

**App runs but the browser can't connect**
Confirm the instance has a public IP, port 3000 is allowed in the security group, and you're using `http://` (not `https://`).

**Service fails to start**
Check `sudo journalctl -u node-app -n 100 --no-pager`. Common causes: no `start` script in `package.json`, or the app ignores the `PORT` environment variable.

---

## Security Notes

- **Restrict SSH.** The security group opens port 22 to `0.0.0.0/0`. For anything beyond a demo, limit it to your own IP (for example `203.0.113.5/32`).
- **Restrict the app port** if the app shouldn't be public, or put it behind a load balancer or Nginx with HTTPS.
- **Host key checking is disabled** (`ANSIBLE_HOST_KEY_CHECKING=False`) for convenience on freshly created instances.
- **Never commit secrets.** `.gitignore` already excludes `*.pem`, `*.key`, Terraform state, and the generated inventory. State files can contain sensitive data, so consider a remote backend (such as S3 with locking) for team use.
- **Review remote scripts.** The playbook runs the NodeSource setup script downloaded over HTTPS.

---

## Contributing

Issues and pull requests are welcome. Please run `terraform fmt` and `terraform validate` before submitting changes, and test against a fresh instance.
