# Anti-Slop

## Stop the Slop.

AI can turn a useful sentence into a paragraph nobody wants to read. Anti-Slop helps you cut the filler and get back to what you meant.

Built by [LiTiL Labs](https://litil.ai), Anti-Slop is an editing skill you can use in your AI assistant. This repo also includes a native Mac app for editing selected text without copying it into a chat.

**[Get the skill](.claude/skills/anti-slop/)** · **[Mac app](app/README.md)** · **[Read the editing rules](prompts/primary.md)**

## Get the skill

The skill gives your assistant a specific editing job: improve the passage while preserving its meaning and your voice. It returns one copyable replacement, or leaves the text alone when an edit would make it worse.

With [Claude Code](https://code.claude.com/docs/en/skills) installed, clone this repo and start a session inside it:

```sh
git clone https://github.com/LiTiL-Labs/antislop.git
cd antislop
claude
```

Claude Code discovers the skill in `.claude/skills/anti-slop/`. Type `/anti-slop` followed by the passage you want edited.

To make it available in your other Claude Code projects, copy the entire [`anti-slop` folder](.claude/skills/anti-slop/) to `~/.claude/skills/anti-slop/`. Keep the supporting files and license notices with it. If you already have that folder, compare it before replacing anything.

The skill runs in the assistant that loads it. It does not require the Mac app or call a second model.

## What it edits

Empty introductions. The conclusion that repeats the introduction. A simple point buried under “it is important to note.” Those are the kinds of patterns Anti-Slop is built to catch.

Its instructions put meaning ahead of style:

- Cut filler, inflated framing and stock transitions when they weaken the passage.
- Preserve the author's point of view, humor and tone.
- Keep names, numbers, citations, quotations and technical identifiers intact.
- Preserve uncertainty, negation and conditions. “May” cannot quietly become “will.”
- Leave a good sentence alone.

That last part matters in legal writing. A defined term is deliberate. So are “shall,” “must,” “only” and “unless.” Making a clause smoother is no improvement if the obligation changes.

Anti-Slop reviews writing patterns. It does not determine whether AI wrote a passage, provide an authorship score, or promise to fool a detector. Review the proposed edit before using it.

## From Caveman to Lawyer

Choose how complex the prose should be:

| Level | What you are asking for |
| --- | --- |
| **Caveman** | The shortest clear sentences and everyday words. Complete thoughts, with the conditions kept. |
| **Plain** | Plain language and mostly short sentences. |
| **Balanced** | Natural sentence variety. The default. |
| **Polished** | A professional register without ornamental language. |
| **Lawyer** | Precise, formal sentences with the qualifications spelled out. |

You can also supply a style guide. It cannot override meaning or protected wording.

Yes, the editing rules remove em dashes from editable prose. Exact quotations, citations, code and other protected literals stay literal.

## Prefer a key to a chat window?

The [Mac app](app/README.md) lives in your menu bar. Select plain text, press your assigned key and review the proposed rewrite in a floating panel. Edit it if you want. Press the key again or click **Anti-slop** to apply it.

A separate **Slop check** key quotes the passages it flags and explains the writing pattern. It makes no changes. When you do apply a rewrite, the app checks that the original selection is still there; if it has changed, the draft stays in the panel.

The app uses the official **Codex** or **Claude Code** runtime with your own signed-in account. Text is sent through the selected provider, so running the app on your Mac does not mean inference is offline.

Requires macOS 13 or later, a supported signed-in runtime and Accessibility permission. TextEdit is the verified plain-text baseline; support in other editors depends on their accessibility controls. See [setup and build instructions](app/README.md), including signing options.

The skill uses the app's editing rules, but the app's selection checks and replacement controls belong to the app.

## Read the code. Check the claims.

The prompts, validation logic and evaluation records are in this repo:

- [Editing prompt](prompts/primary.md) and [Slop check prompt](prompts/detect.md)
- [Skill evaluation](app/evidence/skill-eval-0.3.md), including the cases it missed
- [Architecture and replacement checks](ARCHITECTURE.md)
- [Prompt composition](PROMPTING.md), [current decisions](DECISIONS.md) and [implementation status](app/IMPLEMENTATION_STATUS.md)

The recorded skill evaluation uses synthetic text and model graders; it is not a human editorial-quality study.

## Credits

LiTiL's editing rules incorporate adapted guidance from Peter Yang's **No AI Slop** and Siqi Chen / blader's **Humanizer**. Their MIT notices are included in the [skill](.claude/skills/anti-slop/licenses/) and [third-party sources](third_party/PROVENANCE.md). The upstream authors have not endorsed these adaptations.

