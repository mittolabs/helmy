# Running helmy.ke

## The site

The release is one Docker image (`infra/Dockerfile`): the Jaspr site at the root and the
docs under `/docs/`, built from one commit by `make web`, inside the Caddy that serves
them as plain http (`infra/Caddyfile`). The download page names the latest release's
builds, read from GitHub when the image is built.

`infra/compose.yml` runs it on this machine (`make local`, http://localhost:8745) and on
the server, where it joins the `ashlar` network as `helmy-site`.

## The server

Helmy is a guest on the server the *.ashlar.ke sites share (187.77.160.136), as Rika is.
That server's edge Caddy (`ashlar-site/infra/edge`) holds 80 and 443, gets helmy.ke's
certificate, and passes the requests to `helmy-site:80`. Why a guest, and what it costs:
`docs/notes/helmy-on-the-ashlar-server.md` in the Mittolabs workspace.

## The pipeline

`.github/workflows/site.yml` builds `ghcr.io/mittolabs/helmy-site:<sha>` on every push to
`main` that touches the site, the docs, the changelog or this folder, and after each
release's builds are attached (so the download page lists them). It deploys only when the
repository has these, and until then a release is started by hand:

| Name | Kind | What |
|---|---|---|
| `DEPLOY_HOST` | variable | The server's address. Deploys are off while it is unset |
| `DEPLOY_SSH_KEY` | secret | A private key whose public half is in ashlar-icons-site's inventory (`deploy_public_keys`), applied with its `make provision` |
| `DEPLOY_KNOWN_HOSTS` | secret | `ssh-keyscan` of the server, so CI refuses an impostor |

## By hand

```sh
make deploy HOST=187.77.160.136              # the image CI built for HEAD
make deploy HOST=187.77.160.136 RELEASE=<sha> # roll back to an older one
```

One run is one SSH connection (`infra/ansible/ansible.cfg`). The server drops repeated
connections, so never loop a deploy: back off a minute when refused.
