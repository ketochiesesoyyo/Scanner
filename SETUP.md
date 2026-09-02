# Setting up from zero (beginner-friendly)

This gets you from a brand-new Mac to running Scanner on the iPhone Simulator, and then on a real
iPhone. No prior iOS experience needed. Copy-paste the commands into the **Terminal** app
(press `⌘ + Space`, type "Terminal", press Enter).

> Stuck at any step? Paste the exact error message into your AI assistant (Claude, ChatGPT, Cursor…)
> together with the step number — that's usually enough for it to unblock you.

## What you need

- A Mac (Apple Silicon or Intel) with **macOS 15 or newer** and ~40 GB free disk space (Xcode is huge).
- A free Apple ID (the one you use for the App Store is fine).
- To run on a real iPhone: an iPhone with **iOS 18 or newer** and a USB cable.

## Step 1 — Install Xcode (Apple's app for building iOS apps)

1. Open the **App Store** app on the Mac.
2. Search for **Xcode** and click **Get / Install**. It's ~10 GB — start it and go do something else.
3. When it's done, **open Xcode once**. It will ask to install "additional components" — say yes.
4. When asked which platforms to develop for, make sure **iOS** is checked.

Check it worked — paste this in Terminal:

```sh
xcodebuild -version
```

You should see `Xcode 26` (or newer). If Terminal says "command not found" or shows a tiny version,
run this and try again:

```sh
sudo xcode-select -s /Applications/Xcode.app
```

## Step 2 — Install Homebrew (a tool that installs other tools)

Paste this in Terminal and follow what it prints (it will ask for your Mac password — typing it shows
nothing on screen, that's normal):

```sh
/bin/bash -c "$(curl -fsSL https://raw.githubusercontent.com/Homebrew/install/HEAD/install.sh)"
```

**Important:** at the end, Homebrew prints two or three lines starting with `echo` and `eval` under
"Next steps" — copy and run those too, then close Terminal and open it again.

Check it worked:

```sh
brew --version
```

## Step 3 — Get the code

```sh
brew install xcodegen
cd ~
git clone https://github.com/ketochiesesoyyo/Scanner.git
cd Scanner
xcodegen generate
```

What just happened: `git clone` downloaded the project into a `Scanner` folder in your home
directory, and `xcodegen generate` created `Scanner.xcodeproj` (we don't store that file in git —
you regenerate it, and you'll rerun `xcodegen generate` any time you pull changes or add files).

## Step 4 — Run it in the Simulator (no iPhone needed)

```sh
open Scanner.xcodeproj
```

In Xcode:

1. At the top of the window there's a bar that says **Scanner** and a device name. Click the device
   name and pick any **iPhone Simulator** (e.g. "iPhone 17").
2. Press **⌘R** (or the ▶ button). First build takes a few minutes; then a fake iPhone window opens
   with the app running.
3. The Simulator has no camera — use **Import from Photos** to try the pipeline (drag any photo of a
   document onto the Simulator window first to add it to its photo library).

If this works, your setup is good. ✅

## Step 5 — Run it on your real iPhone

1. **Tell Xcode who you are:** Xcode menu → **Settings…** → **Accounts** → **+** → **Apple Account** →
   sign in with your Apple ID.
2. **Create your signing file:** back in Terminal:

   ```sh
   cd ~/Scanner
   cp Config/Local.xcconfig.example Config/Local.xcconfig
   open -a TextEdit Config/Local.xcconfig
   ```

   Replace `XXXXXXXXXX` with your **Team ID**. Where to find it: Xcode → Settings → Accounts → click
   your Apple ID → your name appears under "Teams" (usually "Your Name (Personal Team)") → the Team ID
   is shown there (a 10-character code). Save and close TextEdit, then run `xcodegen generate` again.
   This file is personal and stays out of git — everyone on the team has their own.
3. **Plug in the iPhone** with a cable and unlock it. Tap **Trust** if the phone asks.
4. On the iPhone, turn on **Developer Mode**: Settings → Privacy & Security → scroll to the bottom →
   Developer Mode → on → restart the phone. (This option only appears after Xcode has seen the phone
   at least once — plug it in first.)
5. In Xcode's device bar, pick **your iPhone** instead of the Simulator, then press **⌘R**.
6. First time only, the app won't open and iOS will complain about an untrusted developer. Fix: on the
   iPhone, Settings → General → **VPN & Device Management** → tap your Apple ID → **Trust**. Run again.

## Everyday workflow after setup

```sh
cd ~/Scanner
git pull            # get the team's latest changes
xcodegen generate   # regenerate the project (always safe to run)
open Scanner.xcodeproj
```

Then read **[AGENTS.md](AGENTS.md)** (how we work) and **[docs/roadmap.md](docs/roadmap.md)** (what's
done, what's next — pick an unclaimed task and put your name in the "Who" column). If you use an AI
coding assistant, it reads AGENTS.md automatically and will know the project rules.

To push your changes you need to be added as a collaborator on the GitHub repo — ask the owner.

## Troubleshooting

| Problem | Fix |
|---|---|
| `xcodegen: command not found` | Rerun Step 2's "Next steps" lines, reopen Terminal, then `brew install xcodegen`. |
| `xcodebuild: error: tool 'xcodebuild' requires Xcode` | `sudo xcode-select -s /Applications/Xcode.app` |
| Xcode shows red "Signing" errors | Step 5.1 and 5.2 weren't finished — check `Config/Local.xcconfig` has your real Team ID, rerun `xcodegen generate`, reopen the project. |
| "Untrusted Developer" when opening the app | Step 5.6 (Settings → General → VPN & Device Management → Trust). |
| Your iPhone doesn't appear in the device bar | Unlock it, tap Trust, use a data-capable cable, and check Developer Mode (Step 5.4). |
| App needs a newer iOS | The phone must be on iOS 18+. Update it: Settings → General → Software Update. |
| Build broke after `git pull` | Run `xcodegen generate` again — a teammate probably added files. |
