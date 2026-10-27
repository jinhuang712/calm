<!-- what-we-build: approved 2026-10-28 -->

# Philosophy

Coding agents changed what a developer does at a terminal. The developer used to type. Now the developer watches several agents work, reads what they write, answers their questions and steers them. The hands rest. The mind does not.

In this work, the scarce thing is attention, not speed. Every glance at a tab, every half-read status and every "is it done yet?" takes a little of it. Over ten sessions and a full day, those small losses become strain. Calm Terminal exists to give that attention back. This page says what calm means, and every change is checked against it.

> The result of calm technology is to put us at home, in a familiar place.
>
> — Mark Weiser and John Seely Brown, *Designing Calm Technology*, 1995

## What is scarce when agents do the typing?

**Attention, not speed.**

An agent types faster than any person, so speed is no longer the developer's limit. What the developer spends is looks: a click on a tab, a status read halfway, a second look to be sure. Each one is small. Ten sessions across a day make thousands of them, and the cost shows as tiredness, not as lost minutes.

The cost of this stance is that Calm does not try to show more. A screen that shows everything gives the work of filtering to the user, and the user filters all day. A calm tool filters for the user: it decides what can wait, and keeps it out of the way.

The other side says that more information means more control, and a good developer wants to see everything. This is true for a short task that one person follows. It fails for ten long tasks, where seeing everything means reading everything. Control then comes from knowing which one to look at.

> Our data suggests that people compensate for interruptions by working faster, but this comes at a price: experiencing more stress, higher frustration, time pressure and effort.
>
> — Gloria Mark, Daniela Gudith and Ulrich Klocke, *The Cost of Interrupted Work: More Speed and Stress*, 2008

## What is calm?

**Calm is knowing, without checking, that nothing needs you.**

Calm is not the absence of activity. Ten agents can work at once in a calm room. Weiser and Brown describe two places of attention: the center, which holds the one thing a person thinks about, and the periphery, which holds what the person knows without looking at it, like rain on a window. A calm tool keeps what it knows in the periphery. It moves a thing to the center only when it matters, and then lets it go back.

The cost is that the tool must judge what matters. A tool that judges wrongly is worse than a loud one, because the user cannot see what it kept back. This is why the next question matters.

The other side says that the quiet tool hides things, and a loud tool at least tells the truth. A tool that is loud about everything tells the truth about nothing, because the user cannot tell the one real question from the noise.

> We use "periphery" to name what we are attuned to without attending to explicitly.
>
> — Mark Weiser and John Seely Brown, *Designing Calm Technology*, 1995

> A calm technology will move easily from the periphery of our attention, to the center, and back.
>
> — Mark Weiser and John Seely Brown, *Designing Calm Technology*, 1995

## Why do people keep checking a quiet tool?

**They check when quiet has lied to them once.**

Quiet is a claim: nothing needs you. A person believes it only while it has held every time. One missed question teaches the person that any silence may hide the next one, and from then on the person checks the source by hand. The tool is still quiet, and it has stopped saving any attention. Trust is learned from the misses, not from the hits.

The cost is that the rare moment must be right. A tool that stays silent for an hour and then misses the one question has done worse than a tool that was never quiet, and the tool must accept being loud for that one moment. When the tool is unsure, a wrong alarm is cheaper than a wrong silence.

The other side says that the way to calm is to turn off every alert. This removes the noise and also the proof. With no alert at all, the user has nothing to believe, so the user looks anyway. Calm needs a few signals that are always right, not none.

The mind has another reason to want this. A task left open keeps a part of the mind busy, and Masicampo and Baumeister found that a concrete plan lets that part stand down. A status the user can trust does the same job for a running agent: the user may put the task down until the tool says otherwise. That is our reading of their result, not their claim.

## What should a tool ask of its user?

**Nothing it could decide itself.**

Each option is a question the tool asks back, and each question takes attention and asks for a decision the user did not come to make. A good default is a decision made once, with care, for everyone. A setting marks the place where the design stopped. Add one only when no single answer is right for most people.

The cost is that a default is wrong for some. Calm accepts this, and keeps the number of settings small, so the people it fails have few places to be failed.

The other side says that skilled users want control, and a default that cannot be changed is arrogance. The stance does not forbid a way to change a default. It forbids asking before the user has a reason to care.

## The test for every change

When answers collide, trust comes first, then quiet, then completeness. A tool that can be wrong about the one thing that matters has no use for its calm.

Before any change, ask:

1. Does it reduce what the user has to track, remember or look at?
2. Does it stay in the periphery unless it needs attention?
3. Can the default be right, so the user decides nothing?
4. Does a tool outside Calm already do this well?

When the answer to 1 or 2 is no, or the answer to 4 is yes, the change does not belong in Calm.

## Reflections

- **Only one person has tested these stances.** The author is the first user and has used Calm daily since 2026-09-29. A second user may find that "check when quiet has lied" is true for the author and not for everyone.
- **No study looks at supervising many agents.** The sources study interruptions in offices and an assistant inside an editor, not a developer who watches ten long-running tasks. The stances apply them by analogy.
- **Speed may still matter.** Mark and colleagues found that interrupted people work faster, at a price in stress. The stance says speed is not the limit. The two agree only if the stress is the real cost, and this has not been tested for agent work.
- **Pu and colleagues are cited, not quoted.** They found that presence indicators and interaction context "alleviated disruptions" from a proactive assistant. Their tool offers help on its own and Calm offers none, so the finding supports the periphery idea only by analogy. No stance rests on it.
- **An earlier version of this page was wrong in one place.** It credited Weiser and Brown with the line "informs but doesn't demand our focus or attention". That line is not in their paper, and this version drops it.
- **Evidence dropped, not refuted.** The earlier version also listed Pousman and Stasko, Iqbal and Bailey, Ma and others, Leroy, Wilms and Oberfeld, Amber Case, Kushlev and others, and Iyengar and Lepper. This session did not check them against the originals, so none is quoted. The choice-overload result (Iyengar and Lepper) has mixed replications, which is a reason to treat the stance on defaults as a design belief, not a proven fact.

## Sources

Quotes from Mark and colleagues were read in the paper's PDF. Quotes from Weiser and Brown were read through a web fetch of calmtech.com's copy, and are not yet checked against a second copy. Sources disagree on their year (1995 in most of this repository, 1997 in some citations). Pu and colleagues and Masicampo and Baumeister are paraphrased from their abstracts, with no quote.

- Mark Weiser and John Seely Brown. *Designing Calm Technology*. 1995.
- Gloria Mark, Daniela Gudith and Ulrich Klocke. *The Cost of Interrupted Work: More Speed and Stress*. CHI 2008.
- Kevin Pu and others. *Assistance or Disruption? Exploring and Evaluating the Design and Trade-offs of Proactive AI Programming Support*. CHI 2025.
- E. J. Masicampo and Roy F. Baumeister. *Consider It Done! Plan Making Can Eliminate the Cognitive Effects of Unfulfilled Goals*. Journal of Personality and Social Psychology, 2011.
