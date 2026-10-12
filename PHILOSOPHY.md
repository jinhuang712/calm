# Philosophy

Coding agents changed what a developer does at a terminal. The developer used to type. Now the developer watches several agents work, reads what they write, answers their questions and steers them. The hands rest. The mind does not.

In this work, the scarce thing is attention, not speed. Every glance at a tab, every half-read status and every "is it done yet?" takes a little of it. Over ten sessions and a full day, those small losses become strain.

Calm Terminal exists to give that attention back. This page says what calm means. Every change is checked against it, and when a proposal conflicts with a principle, the principle wins.

## What calm means

Mark Weiser wrote that "the most profound technologies are those that disappear" (1991). With John Seely Brown, he described calm technology as "that which informs but doesn't demand our focus or attention" (1995).

Calm technology works with two places of attention. The periphery holds what we know without looking at it, like rain on the window or a clock in the next room. The center holds the one thing we are thinking about. A calm tool keeps information in the periphery and moves it to the center only when it matters. Then it lets it go back.

Calm is not the absence of activity. Ten agents can work at once in a calm room. Calm is knowing, without checking, that nothing needs you right now.

## Principles

### 1. Attention is the scarce resource

A screen that shows everything gives the work of filtering to the user. The user then filters all day, and that work is invisible and tiring. A calm tool does the filtering itself. It decides what can wait and keeps it at the edge. It brings forward only what needs a person, and it does so at a natural pause, because an interruption costs more in the middle of a thought than at its end.

### 2. Reliable, so the user can stop checking

Quiet is a promise. When a tool is quiet, the user must be able to believe that all is well. A tool that misses one important moment teaches the user to check everything again, and the calm is gone. Silence without trust is anxiety. Trust grows only from a record that holds every time. A record the mind trusts lets it put down what it was holding.

### 3. The default is the product

Each option is a question that the tool asks back. Each question takes attention and asks for a decision that the user did not come to make. A good default is a decision made once, with care, for everyone. A setting marks the place where the design stopped. Add one only when no single answer is right for most people.

### 4. Calm stays a terminal

A tool that tries to do everything competes with the work it should support. The agents already have their own voices and interfaces. Calm does not speak over them. It improves the room they work in: what is seen, what is remembered and what is easy to reach. Doing less keeps the rest trustworthy.

## Design guidelines

Four words guide how Calm looks and moves.

| Word | Means |
|---|---|
| **Restraint** | Show only what helps. When in doubt, leave it out. |
| **Elegance** | Care in every detail. Nothing jumps, flashes or crowds. |
| **Minimalism** | Every element earns its place. |
| **Calm** | The interface lowers the pulse. |

## Evidence

The principles rest on research about attention, interruption, trust and choice.

| Rule | Source |
|---|---|
| Keep information in the periphery. Bring to the center only what needs the user. | Weiser & Brown, *Designing Calm Technology* (1995); Amber Case, *Calm Technology* (2015) |
| Grade interruptions by importance. Only the top grade interrupts. | Pousman & Stasko, *A Taxonomy of Ambient Information Systems* (AVI 2006) |
| Every interruption has an emotional cost, even when productivity looks unaffected. | Mark, Gudith & Klocke, *The Cost of Interrupted Work* (CHI 2008) |
| Interrupt at natural pauses, not in the middle of a task. | Iqbal & Bailey, *Oasis* (ACM TOCHI 2010) |
| Fewer alerts reduce inattention. Turning all alerts off raises anxiety, so be reliable. | Kushlev et al., *Silence Your Phones* (CHI 2016); Fitz et al., *Batching Smartphone Notifications* (2019) |
| Interruptions slow developers' understanding of code. | Ma, Huang & Leach, *Breaking the Flow* (ICSE 2024) |
| Presence plus context reduces the disruption that AI agents cause. | Pu et al., *Assistance or Disruption?* (CHI 2025) |
| After a task switch, context helps attention leave the previous task. | Leroy, *Attention Residue* (2009) |
| A trustworthy record of open work frees the mind from tracking it. | Masicampo & Baumeister, *Consider It Done!* (2011) |
| Saturated, bright colors raise arousal. Keep colors soft and save alarm for real problems. | Wilms & Oberfeld, *Color and Emotion* (2018) |
| Fewer choices lead to more satisfaction. This is a tendency, and replications are mixed. | Iyengar & Lepper, *When Choice Is Demotivating* (2000) |

## The test for every change

Before any change, ask:

1. Does it reduce what the user has to track, remember or look at?
2. Does it stay in the periphery unless it needs attention?
3. Can the default be right, so the user decides nothing?
4. Does a tool outside Calm already do this well?

When the answer to 1 or 2 is no, or the answer to 4 is yes, the change does not belong in Calm.
