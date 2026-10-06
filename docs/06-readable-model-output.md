# Making Model Output Easier to Read: A Cheat Sheet

English | [简体中文](zh-CN/06-让模型输出更好读.md)

The details of the ASD-STE100 rules have not been checked against the specification itself.

Purpose: when you need to understand a long output (a research report, a proposal, an explanation of an unfamiliar system), copy one line from here into your request.

## Core idea

The more work the model does, the more a person's work concentrates on supervision and understanding, and the bottleneck becomes the speed of reading the output. Code and intelligence have become cheap, so you can have the model produce a one-off artifact whose only purpose is to help you understand.

## Four output forms (lower is easier to read, and more expensive)

| Tier | How to ask | Good for |
| --- | --- | --- |
| 1. Controlled technical writing | See the prompts below | An explanation you cannot follow, a report that is too convoluted |
| 2. Diagram | "Draw a diagram that explains X" | Structure, flow, hierarchy, comparison |
| 3. Web page | "Give the conclusion as one HTML page, with a comparison table and a structure diagram" | A research report you must understand before making a decision |
| 4. Explainer video | "Make a 3b1b-style video explaining X" (voice-over needs an ElevenLabs key or a local substitute) | Learning an unfamiliar concept; its usefulness for everyday work is currently unclear |

## Prompts you can copy directly

For reading English material:

```
Explain this in about 80% ASD-STE100.
```

When you want output in a language other than English (the standard covers English only, so spell the rules out):

```
Write following the rules of controlled technical writing: use the same word
for the same thing every time; one sentence says one thing; one paragraph covers
one topic, at most 6 sentences; write steps in the active voice, one step per
line; give the conclusion first, then the evidence.
```

For a piece of output you already have:

```
Rewrite this passage using the rules above.
```

At the end of a research task you hand off:

```
Deliver the final conclusion as one HTML page: a three-sentence conclusion at
the top, then a comparison table, then a structure diagram; list anything you
could not find or confirm separately, and state where you looked.
```

## What ASD-STE100 is

A controlled-English specification maintained by the European aerospace industry association (ASD). It originated in aircraft maintenance manuals of the 1980s and was designed for maintenance staff whose first language is not English.

- Writing rules: at most 20 words in a step sentence, at most 25 words in a descriptive sentence, at most 6 sentences per paragraph; one instruction per sentence; steps use the active voice and imperative; no continuous or perfect tenses; no more than 3 stacked nouns.
- Dictionary: about 900 approved words, each with a single part of speech and a single meaning (`close` only as a verb; `commence` is written as `start`; `prior to` is written as `before`).
- Safety statements: `WARNING` marks a risk of injury to people, `CAUTION` marks a risk of equipment damage; write the instruction first, then the reason.

Why it helps in prompts: the model has seen this specification, so one name carries dozens of writing instructions at once. It targets exactly the faults of model writing: long sentences, swapping between synonyms, several things in one sentence, and stacks of abstract nouns.

## Caveats

- Add it only temporarily, when you need to understand a long output, and **do not put it in global rules**. Someone reported that thinking quality dropped when the constraint was applied throughout (a single personal experience); the constraint should apply only to the final version meant for a person to read.
- Use "80%" rather than 100%: the original specification was designed for operating procedures, and applying all of it to content that needs trade-offs, such as option comparisons and decision advice, reads stiffly.
- The model only approximates the style; it does not look words up in the dictionary one by one.
- Looking good is not the same as being right. A polished explanation that conveys the wrong understanding is more dangerous, so HTML and video cannot replace independent verification.
- HTML and video use many output tokens, and output is the most expensive kind, so use them only for content worth understanding.

## Possible extra use (not confirmed)

The specification's home field is equipment operation and safety instructions. If you are writing English manuals for equipment, or English operating prompts shown on a screen, you can evaluate separately whether to write them this way.

## Not verified

None of the prompts above has been tried on a real task yet. After the first trial, add the results: whether reading really got faster, and whether any information was lost.
