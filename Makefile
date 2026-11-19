.PHONY: hooks test test-classes analyze lint-new api-check

# The branch lint-new and api-check compare with.
BASE ?= origin/main

# Once per clone: git push runs scripts/lint-new.sh (.githooks/pre-push).
hooks:
	sh .githooks/install.sh

# The whole suite on a simulator, as CI and the release workflow run it (.github/scripts/test.sh).
test:
	.github/scripts/test.sh

# Only these XCTest classes: make test-classes CLASSES="GleapGrantTests GleapUserJwtTests"
test-classes:
	bash scripts/test-classes.sh $(CLASSES)

# Every compiler and static analyzer warning, old code included. For reading; nothing gates on it.
analyze:
	sh scripts/analyze.sh

# What git push, the stop hook and the Quality workflow run: only what this branch adds compared with $(BASE).
lint-new:
	sh scripts/lint-new.sh $(BASE)

# The public API compared with $(BASE); part of lint-new when a public header changed.
api-check:
	sh scripts/api-check.sh $(BASE)
