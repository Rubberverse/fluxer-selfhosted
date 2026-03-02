# fluxer-selfhosted
Experimenting around with self-hosting Fluxer early

## More about this small project

The current Dockerfile is pretty outdated, won't build without modifications to it. It's a bit of a mess here 'n' there but nothing you can't fix yourself. I wish it ran by rootless user by default inside container though. (my containerfile does that :p)

I've relied on my self-hosted LLM for advice regarding fixing `pnpm` build errors, it got me a bit there but the rest was community and their pro-tips in regards to fixing everything. It was randomly threw up at 3 in the morning and well I've just fixed it up and made it actually build the server. There's few errors here 'n' there, mainly with `.dockerignore` that the main repository has but nothing you can't go arouund.

Shoutouts to this [guide](https://github.com/orgs/fluxerapp/discussions/542) on Fluxer's discussions.

I've seen pretty misleading comments about this so let me clarify, the `fluxer_server` container intended for self-hosting bundles following components into a single container image:

- fluxer_server (back-end, pnpm/nodejs/whatever mix)
- fluxer_app (front-end in Rust, I suppose it also makes use of fluxer_app_proxy)
- fluxer_gateway (not sure what it does, `rebar3` is used to compile it though. Might be related to payment gateway?)
- fluxer_media_proxy (if you use nsfw detection model then it just copies the model to /opt/data/model.onnx but doesn't build the app. maybe it does but iunno. Not a nodejs guy.)

Probably more, or less. It's a giant monolith, which means it's few services running inside a singular container. It makes deployment easier but well is considered a bad approach if we look at it from container spec perspective. But well you pay for convenience a little bit, don't ya?

## What the Containerfile does

It can be a direct replacement for the Dockerfile inside `fluxer_server` directory. It builds from root of the project.

I've updated it to mimmick build process of the official image better and also for it to be much more readable. At the production stage, it chowns various directories as `node:node` user and changes permissions to `read, execute`. Then it runs as `node:node` user and uses `tini` with `TINI_SUBREAPER=1` to yeet some stale processes if they ever pop up inside the container. At production stage, instead of running it as root, it chowns everything as `node:node` user with 555 permissions before forking off to node:node user and running the image. It also installs rust toolchain very early on in the image, I didn't bother installing wasm-pack as it manually figures it out and does it by itself.

You still must fix the source manually yourself.

## Should you run this?

Without any manual fixing done by you based on community findings, not really. If you're also not familiar with self-hosting such a monolith at a larger scale then this will be a nice challenge for you, it's not that hard it's just *annoying* in it's current state.

## Building the image

No pre-built images as Fluxer still makes use of hardcoded defautls for a lot of things. It's actually pretty terrible but whatever. You will mainly need to manually fix CSP as it is still hardcoded to load assets from `fluxerstatic.com` from what I've seen (either at reverse proxy level, or at build time, both are easy enough to do)

### Preparation

Make a directory called fluxer and cd into it `mkdir -p ~/fluxer && cd ~/fluxer` then just clone fluxer repository `GIT_LFS_SKIP_SMUDGE=1 git clone --depth 1 --branch refactor https://github.com/fluxerapp/fluxer.git .`

Apply fixes from 'Modifying files' afterwards.

In case you wanna build desktop client properly then [this fork makes it possible](https://github.com/mgabor3141/fluxer).w

### Modifying files

[Follow this instead and if you're stuck, read below](https://github.com/orgs/fluxerapp/discussions/542#discussioncomment-15922947)

You may also need to add following to your `.dockerignore`:

```bash
!fluxer_gateway/rebar.lock*
!fluxer_app/scripts/build
!fluxer_app/scripts/build/**
```

When it comes to fixing SSO:

`fluxer_app/src/router/components/RootComponent.tsx`:

The 'allow list' they talk about is this start of the snippet:

```bash
  const isStandaloneRoute = useMemo(() => {
    return (
      pathname.startsWith(Routes.LOGIN) ||
      pathname.startsWith(Routes.REGISTER) ||
      pathname.startsWith(Routes.FORGOT_PASSWORD) ||
      pathname.startsWith(Routes.RESET_PASSWORD) ||
      pathname.startsWith(Routes.VERIFY_EMAIL) ||
      pathname.startsWith(Routes.AUTHORIZE_IP) ||
      pathname.startsWith(Routes.EMAIL_REVERT) ||
      pathname.startsWith(Routes.OAUTH_AUTHORIZE) ||
      pathname.startsWith(Routes.REPORT) ||
      pathname.startsWith(Routes.PREMIUM_CALLBACK) ||
      pathname.startsWith(Routes.CONNECTION_CALLBACK) ||
      pathname === '/__notfound' ||
      pathname.startsWith('/invite/') ||
      pathname.startsWith('/gift/') ||
      pathname.startsWith('/theme/')
    );
  }, [pathname]);
```

You append `pathname.startsWith('/auth/sso/callback') ||` below `pathname.startsWith(Routes.CONNECTION_CALLBACK) ||`. Below is how it looks like with that extra added.

```bash
  const isStandaloneRoute = useMemo(() => {
    return (
        pathname.startsWith(Routes.LOGIN) ||
        pathname.startsWith(Routes.REGISTER) ||
        pathname.startsWith(Routes.FORGOT_PASSWORD) ||
        pathname.startsWith(Routes.RESET_PASSWORD) ||
        pathname.startsWith(Routes.VERIFY_EMAIL) ||
        pathname.startsWith(Routes.AUTHORIZE_IP) ||
        pathname.startsWith(Routes.EMAIL_REVERT) ||
        pathname.startsWith(Routes.OAUTH_AUTHORIZE) ||
        pathname.startsWith(Routes.REPORT) ||
        pathname.startsWith(Routes.PREMIUM_CALLBACK) ||
        pathname.startsWith(Routes.CONNECTION_CALLBACK) ||
        pathname.startsWith('/auth/sso/callback') ||
        pathname === '/__notfound' ||
        pathname.startsWith('/invite/') ||
        pathname.startsWith('/gift/') ||
        pathname.startsWith('/theme/')
    );
  }, [pathname]);
```

User.tsx is in `packages/api/src/models/User.tsx` and they talk about this line:

```bash
	isUnclaimedAccount(): boolean {
		return this.passwordHash === null && !this.isBot;
	}
```

You just add `&& !this._traits.has('sso')` to `return this.passwordHash === null && !this.isBot;`

```bash
	isUnclaimedAccount(): boolean {
		return this.passwordHash === null && !this.isBot && !this._traits.has('sso');
	}
```


### Actually building the multi-service container

Now you can finally build it. It's simple but will waste some time, your CPU will probably be maxed as it has to compile things. You'll also need plenty of space. Each build stage consumes 2GB+ so let me see...

```bash
localhost/fluxer                                    dev              bdd6bda22b78  About an hour ago  2.32 GB
<none>                                              <none>           68fe42045ec8  About an hour ago  6.68 GB
<none>                                              <none>           e42ba59d904e  About an hour ago  2.41 GB
<none>                                              <none>           4449bdb9b72d  2 hours ago        2.28 GB
<none>                                              <none>           793ee0a9f54f  2 hours ago        4.91 GB
<none>                                              <none>           d0b8f77f0b65  2 hours ago        2.41 GB
```

Around ~11,41GB per build if we count only first three layers, otherwise it's `21,01GB` per build. The final resulting image is 2.32GB in size. Bulky, isn't it? That's whole build with NSFW model included (which is just 17 megabytes in size)

Anyhow, to build it you need to run following command:

```bash
podman build -f Dockerfile --build-arg BASE_DOMAIN="chat.yourdomain.tld" --build-arg FLUXER_CDN_ENDPOINT="" --build-arg INCLUDE_NSFW_ML=true -t localhost/fluxer:dev
```

This took me around 15 minutes to complete on 2 cores of i3-7100 so if you have slower CPU than that then well, good luck I guess.

## Running it

It makes use of Valkey (Redis-compatible alternative pretty much, presumably for caching and session storage), Meilisearch (for search functionality), LiveKit as a SFU for your typical Voice & Video Chat needs, Nats for Pub/Sub messaging and persistent job queue [if this gist is to be any believed, not sure if the gist author did bare minimum of fact checking the LLM here](https://gist.github.com/PaulMColeman/e7ef82e05035b24300d2ea1954527f10)

You'll almost likely will want to mount a valid config and point the `FLUXER_CONFIG` to it.

```bash
podman run --rm localhost/fluxer:dev
! Corepack is about to download https://registry.npmjs.org/pnpm/-/pnpm-10.29.3.tgz

> fluxer_server@0.0.0 start /usr/src/app/fluxer_server
> tsx src/startServer.tsx

/usr/src/app/packages/config/src/ConfigLoader.tsx:37
                throw new Error('FLUXER_CONFIG must be set to a JSON config path.');
                      ^

Error: FLUXER_CONFIG must be set to a JSON config path.
    at loadConfig (/usr/src/app/packages/config/src/ConfigLoader.tsx:37:9)
    at <anonymous> (/usr/src/app/fluxer_server/src/Config.tsx:22:22)
    at ModuleJob.run (node:internal/modules/esm/module_job:430:25)
    at async onImport.tracePromise.__proto__ (node:internal/modules/esm/loader:661:26)
    at async asyncRunEntryPointWithESMLoader (node:internal/modules/run_main:101:5)

Node.js v24.14.0
/usr/src/app/fluxer_server:
 ERR_PNPM_RECURSIVE_RUN_FIRST_FAIL  fluxer_server@0.0.0 start: `tsx src/startServer.tsx`
 ```

//todo

## Why does Containerfile have weird spacing?

I threw it up randomly one of these nights so formatting is just utterly screwed up in places. I've tried fixing it up but ya, it is what it is. I've had more proper copy somewhere but I've lost it so this notepad++ backup is the best ya gonna get.
