class_name BuildInfo
extends RefCounted
## Which build this is. Empty in the repository; the workflow (.github/workflows/godot-check.yml,
## "Stamp the build number") writes the run number and commit here just before it exports, so the
## Mac app and the web build know the number on their GitHub Release ("build-<n>"). A local run
## says "dev". The verify pack (VerifyPack) names its folder and its report from it.

const BUILD := ""
const COMMIT := ""


## "396", or "dev" in a build nobody stamped.
static func number() -> String:
	return BUILD if BUILD != "" else "dev"


## "Build 396 (e5bb9e4)", or "Dev build" for a local run.
static func label() -> String:
	if BUILD == "":
		return "Dev build"
	return "Build %s (%s)" % [BUILD, COMMIT] if COMMIT != "" else "Build %s" % BUILD
