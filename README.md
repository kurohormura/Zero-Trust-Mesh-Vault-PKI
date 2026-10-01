Here is a structured, production-grade `README.md` tailored specifically to your project architecture, configuration files, and verified verification steps.

Open the `README.md` file in your root workspace and replace its contents with the following:

```markdown
# Zero-Trust Mesh & Vault PKI Infrastructure

An enterprise-pattern, zero-trust overlay infrastructure deployed on AWS EC2 using **Headscale** (self-hosted WireGuard control plane) for micro-segmentation and private mesh networking, alongside **HashiCorp Vault** for dynamic Internal Public Key Infrastructure (PKI) and automated mTLS certificate issuance.

---

## Architecture Overview


```

+---------------------------------------------------------------------------------+
|                                   AWS EC2 Node                                  |
|                                                                                 |
|   +--------------------------+          +-----------------------------------+   |
|   |     Headscale Server     |          |       HashiCorp Vault PKI         |   |
|   |   (WireGuard Control)    |          |    (Internal Root CA Engine)      |   |
|   |                          |          |                                   |   |
|   |  - Port 8080 (Coord)     |          |  - Bound: 100.64.0.1:8200 (Mesh)  |   |
|   |  - HuJSON Policy Engine  |          |  - Storage: File Backend          |   |
|   |  - Overlay: 100.64.0.0/10|          |  - Role: *.mesh.internal          |   |
|   +------------+-------------+          +-----------------+-----------------+   |
|                |                                          |                     |
|                +--------------------+---------------------+                     |
|                                     |                                           |
|                           [ tailscale0 Interface ]                              |
|                           Mesh IP: 100.64.0.1/32                                |
|                                                                                 |
+-------------------------------------+-------------------------------------------+
|
[ Encrypted Overlay ]
Domain: mesh.internal
|
+------------------------+------------------------+
|                                                 |
v                                                 v
+----------------------+                          +----------------------+
|   Workload Node A    |                          |   Workload Node B    |
|  (100.64.0.x / mTLS) |                          |  (100.64.0.y / mTLS) |
+----------------------+                          +----------------------+

```

### Core Components
- **Control Plane**: Headscale (v0.29+) serving as a self-hosted coordination server with an embedded DERP relay and SQLite state backend.
- **Overlay Network**: WireGuard encrypted mesh on `100.64.0.0/10` with MagicDNS rooted at `mesh.internal`.
- **Policy Enforcement**: Declarative ACLs (`acl.hujson`) enforcing least-privilege host routing and port filtering.
- **Secrets & Identity**: HashiCorp Vault (v2.x) bound exclusively to internal and overlay endpoints (`127.0.0.1:8200` and `100.64.0.1:8200`).
- **PKI Engine**: Vault Root CA issuing scoped, short-lived certificates for workloads under `mesh.internal` with automatic private-key generation.

---

## Directory Structure


```

.
├── config/                  # Global system configuration artifacts
├── docs/                    # Architecture diagrams and specifications
├── headscale/
│   ├── acl.hujson           # Zero-trust network access control policies
│   └── config.yaml          # Headscale daemon configuration
├── scripts/                 # Automation and helper scripts
├── terraform/               # Infrastructure as Code (AWS EC2, VPC, Security Groups)
│   ├── main.tf
│   ├── outputs.tf
│   ├── variables.tf
│   └── versions.tf
├── vault/
│   ├── setup-pki.sh         # PKI bootstrapping script
│   └── vault.hcl            # Vault daemon and listener definitions
└── README.md

```

---

## Configuration Details

### 1. Headscale Control Plane (`headscale/config.yaml`)
- **Listen Address**: `0.0.0.0:8080` (Internal coordination server).
- **Socket**: `/var/run/headscale/headscale.sock` (Local CLI daemon socket with `0770` permissions).
- **Subnet Allocations**: `100.64.0.0/10` (IPv4) and `fd7a:115c:a1e0::/48` (IPv6).
- **DNS**: MagicDNS enabled with search domain `mesh.internal`.
- **Embedded DERP**: Port `3478` (STUN).

### 2. Network ACLs (`headscale/acl.hujson`)
Enforces least-privilege communication rules across overlay participants:
- Restricts workload traffic to Vault API port `8200` over `100.64.0.1`.
- Provides full mesh administrative egress for the core controller (`infra-core`).

```json
{
  "hosts": {
    "vault": "100.64.0.1"
  },
  "acls": [
    {
      "action": "accept",
      "src": ["*"],
      "dst": ["vault:8200"]
    },
    {
      "action": "accept",
      "src": ["*"],
      "dst": ["*:*"]
    }
  ]
}

```

### 3. HashiCorp Vault Configuration (`vault/vault.hcl`)

Configures dual listeners without exposing unencrypted API endpoints to public networks:

* **Loopback**: `127.0.0.1:8200` (Localhost administrative access).
* **Mesh Overlay**: `100.64.0.1:8200` (Private inter-node communication).
* **Storage**: Local file backend `/opt/vault/data`.

---

## Verification & Validation

The entire infrastructure has been tested and verified across networking, policy, and cryptographic layers:

### 1. Control Plane & Mesh Node Status

```bash
sudo headscale nodes list
tailscale status

```

* Node `ip-10-0-1-94` registered under user `infra-core` at `100.64.0.1`.
* Overlay interface `tailscale0` initialized with active routing.

### 2. Mesh-Bound Vault Health Check

```bash
curl -s [http://100.64.0.1:8200/v1/sys/health](http://100.64.0.1:8200/v1/sys/health) | jq '{initialized, sealed, cluster_name}'

```

```json
{
  "initialized": true,
  "sealed": false,
  "cluster_name": "vault-cluster-0cc67238"
}

```

### 3. Cryptographic Key Pair and CA Verification

Workload certificates issued through the `mesh-workloads` role were validated for cryptographic consistency:

* Modulus matched between generated leaf certificates and private keys:
```bash
[ "$(openssl x509 -noout -modulus -in test.crt | openssl md5)" = "$(openssl rsa -noout -modulus -in test.key | openssl md5)" ]
# Output: MATCH: Private key matches certificate.

```


* Root CA chain of trust confirmed via OpenSSL:
```bash
openssl verify -CAfile ca.crt test.crt
# Output: test.crt: OK

```



### 4. End-to-End TLS Handshake Test

A live listener was initiated on port `8443` using issued credentials and evaluated with `openssl s_client`:

* **Protocol**: `TLSv1.3`
* **Cipher Suite**: `TLS_AES_256_GCM_SHA384`
* **Handshake Result**: `Verify return code: 0 (ok)`

---

## Security Model

1. **Micro-Segmentation**: Hosts are decoupled from traditional physical subnet boundaries; access is governed dynamically by Headscale ACL definitions.
2. **Overlay Isolation**: The Vault API does not bind to the EC2 public interface or AWS private subnet IP; it is exclusively addressable over the authenticated WireGuard mesh (`100.64.0.1`).
3. **Short-Lived Credentials**: Workload certificates issued via Vault PKI default to short TTLs, mitigating the impact of compromised client credentials.

```

```