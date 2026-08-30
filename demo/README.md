# One-Bit Bureau showcase fixture

This directory supplies deterministic, offline content for the disposable Omarchy Test Lab gallery. It is not installed into a user's home directory.

The acceptance run opens the two local pages in Chromium and converts `showcase-notes.html` into a temporary Writer document. The rest of the showcase uses ordinary applications from Omarchy's base install. This keeps release screenshots useful and believable without depending on network services, accounts, optional packages, or fake application windows.

Functional QA scenes still run first. The showcase pass then stashes those desktop objects, opens the real applications, captures the public-facing gallery states, closes the applications, and restores the QA fixture before lifecycle testing continues.
