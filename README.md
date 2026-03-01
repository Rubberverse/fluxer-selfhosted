# fluxer-selfhosted
Experimenting around with self-hosting Fluxer early

## More about this small project

The current Dockerfile is pretty outdated, won't build without substantial modifications to it. I've spent a bit of time actually working around it 'cus quite frankly, it's a mess on a greater scale. I've mostly relied on my self-hosted LLM for advice regarding fixing pnpm build errors for a monorepo which more or so ended up allowing me to get 50% there - the Containerfile is still written by me. I use it for debugging, not vibecoding and even then I'd rather use a search engine.  (once again, it was late night when I had a knack to try this so since it was running, why not try it. well it got some things right and other so terribly wrong that I started running in circles after a bit xd)

I had issues with building the image as suddenly the language directories were always missing 'cus apparently `.dockerignore`  excludes them (???)

Thanks to this AI generated [gist](https://gist.github.com/PaulMColeman/e7ef82e05035b24300d2ea1954527f10) I've found on the internet for helping me figure out the last missing piece, which was the build failing 'cus `pnpm compile:lungui` silently didn't do anything.

+ Shoutouts to this [guide](https://github.com/orgs/fluxerapp/discussions/542) on Fluxer's discussions.

I've seen pretty misleading comments about this so let me clarify, the `fluxer_server` container intended for self-hosting bundles following components into a single container image:

- fluxer_server (back-end, pnpm/nodejs/whatever mix)
- fluxer_app (front-end in Rust, I suppose it also makes use of fluxer_app_proxy)
- fluxer_gateway (not sure what it does, `rebar3` is used to compile it though. Might be related to payment gateway?)
- fluxer_media_proxy (if you use nsfw detection model then it just copies the model to /opt/data/model.onnx but doesn't build the app. maybe it does but iunno. Not a nodejs guy.)

Probably more, or less. It's a giant monolith, which means it's not just "fluxer_server" and that's it. It's actually 4-5 (maybe more) components running in a single container image. Similar to stoat but stoat still makes you run each component seperately (which is good for what it is. That's the point of containers, isolation between each other, though it adds a lot of friction and complexity to deployment.)

## What the Containerfile does

At production stage, instead of running it as root, it chowns everything as `node:node` user with 555 permissions before forking off to node:node user and running the image. It also installs rust toolchain very early on in the image, I didn't bother installing wasm-pack as it manually figures it out and does it by itself.

## Should you run this?

Probably not. A lot of things are hardcoded in code so some silly things such as [timing out while uploading a file](https://github.com/fluxerapp/fluxer/issues/582) can occur. [SSO functionality is apparently also broken](https://github.com/fluxerapp/fluxer/issues/556). refactor repo changed a lot of things around but there are still critical bugs and issues with hardcoded values flying here 'n' there. Use de-federated Matrix in the meantime.

## Building the image

No pre-built images as Fluxer still makes use of hardcoded defautls for a lot of things. It's actually pretty terrible but whatever. You will mainly need to manually fix CSP as it is still hardcoded to load assets from `fluxerstatic.com` from what I've seen (either at reverse proxy level, or at build time, both are easy enough to do)

### Preparation

Make a directory called fluxer and cd into it `mkdir -p ~/fluxer && cd ~/fluxer` then just clone fluxer repository `git clone https://github.com/fluxerapp/fluxer` (or alternatively, use community fixed fork - `git clone https://github.com/mgabor3141/fluxer`, it fixes a lot of issues with current upstream) 

### Modifying files

[Follow this instead](https://github.com/orgs/fluxerapp/discussions/542#discussioncomment-15922947)

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

It makes use of Valkey (Redis-compatible alternative pretty much, presumably for caching and session storage), Meilisearch (for search functionality), LiveKit as a SFU for your typical Voice & Video Chat needs, Nats for Pub/Sb messaging and persistent job queue [if this gist is to be any believed, not sure if the gist author did bare minimum of fact checking the LLM here](https://gist.github.com/PaulMColeman/e7ef82e05035b24300d2ea1954527f10)

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
