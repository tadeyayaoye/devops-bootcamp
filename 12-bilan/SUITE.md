# Et après ?

## Approfondir sans dépenser

| Sujet | Ressource gratuite |
|---|---|
| Kubernetes en profondeur | Kubernetes the Hard Way ; documentation officielle (Tasks) ; killercoda.com (scénarios interactifs) |
| Cloud (là où tourneront tes clusters en entreprise) | AWS / Azure / GCP : comptes gratuits + LocalStack Community pour simuler AWS en local ; refaire le module 04 avec un vrai provider cloud |
| Service mesh | Istio ou Linkerd sur ton cluster kind (mTLS, trafic, observabilité) |
| Déploiement progressif | Argo Rollouts : canary piloté par une analyse Prometheus |
| Secrets « entreprise » | HashiCorp Vault (mode dev) + External Secrets Operator |
| Policy as code | Kyverno : interdire les images non signées / non GHCR |
| Plateforme interne | Backstage (portail développeur), Crossplane |
| SRE | Google SRE Book + Workbook (gratuits en ligne) |

## Certifications reconnues (payantes, mais ce bootcamp couvre une bonne partie du programme)

| Certification | Ce bootcamp couvre… |
|---|---|
| **CKA** (Certified Kubernetes Administrator) | modules 02-03 (il manque : etcd backup/restore, kubeadm upgrade, troubleshooting de nœuds) |
| **CKAD** (Application Developer) | modules 02-03 quasi intégralement |
| **CKS** (Security) | partie Pod Security, NetworkPolicy, supply chain (07) |
| **HashiCorp Terraform Associate** | module 04 (+ backends distants, HCP Terraform) |
| **Prometheus Certified Associate (PCA)** | module 09 |
| **Argo / GitOps (CAPA)** | module 08 |
| **GitHub Actions** | module 07 |

Astuce : les examens CNCF sont pratiques (terminal) : la vitesse en `kubectl` (alias, `--dry-run=client -o yaml`, `kubectl explain`) compte énormément.

## Garder le bootcamp vivant

- Reviens au **module 11** dans 1 mois : refais la phase 1 (reconstruction) et un incident aléatoire. Si tout passe en < 1 h, c'est acquis.
- Laisse **Dependabot** tourner sur ton repo : chaque PR de mise à jour est un mini-exercice (lire le changelog, CI verte, merge, promotion).
- Ajoute une ligne au README de ton repo : « Ce que j'ai appris / ce que je ferais autrement en production ». C'est précieux en entretien.
