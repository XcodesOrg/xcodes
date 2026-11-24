import contextlib
import importlib.machinery
import importlib.util
import io
import json
import os
from pathlib import Path
import shutil
import subprocess
import tempfile
import unittest
from unittest.mock import patch


ROOT = Path(__file__).resolve().parents[2]
loader = importlib.machinery.SourceFileLoader("release", str(ROOT / "Scripts/release"))
spec = importlib.util.spec_from_loader(loader.name, loader)
release = importlib.util.module_from_spec(spec)
loader.exec_module(release)

MANIFEST = '''
        .package(url: "https://github.com/XcodesOrg/XcodesLoginKit.git", revision: "v1.2.0"),
        .package(url: "https://github.com/XcodesOrg/XcodesKit.git", .upToNextMinor(from: "1.2.0"))
'''
PINS = json.dumps({"pins": [
    {"identity": name.lower(), "location": f"https://github.com/XcodesOrg/{name}.git",
     "state": {"revision": digit * 40}}
    for name, digit in zip(release.DEPENDENCIES, ("a", "b"))
]})
FORMULA = f'''class Xcodes < Formula
  url "https://github.com/XcodesOrg/xcodes.git", tag: "2.2.0"
  head "https://github.com/XcodesOrg/xcodes.git", branch: "main"

  bottle do
    root_url "https://github.com/XcodesOrg/xcodes/releases/download/2.2.0"
    sha256 cellar: :any_skip_relocation, arm64_mojave: "{"c" * 64}"
    sha256 cellar: :any_skip_relocation, mojave:       "{"c" * 64}"
  end

  depends_on macos: :ventura

  resource "XcodesLoginKit" do
    url "https://github.com/XcodesOrg/XcodesLoginKit.git",
        revision: "{"c" * 40}"
  end

  resource "XcodesKit" do
    url "https://github.com/XcodesOrg/XcodesKit.git",
        revision: "{"d" * 40}"
  end

  def install
    package_swift.atomic_write package_swift.read
      .gsub('.package(url: "https://github.com/XcodesOrg/XcodesLoginKit.git", branch: "main")',
            '.package(path: "XcodesLoginKit")')
      .gsub('.package(url: "https://github.com/XcodesOrg/XcodesKit.git", .upToNextMinor(from: "1.1.0"))',
            '.package(path: "XcodesKit")')
  end
end
'''


class ReleaseTests(unittest.TestCase):
    def test_formula_tracks_the_locked_source_and_is_idempotent(self):
        rendered = release.rewrite_formula(FORMULA, MANIFEST, PINS, "2.2.1", "e" * 64)
        self.assertIn(f'all: "{"e" * 64}"', rendered)
        self.assertIn('tag: "2.2.1"', rendered)
        self.assertIn('depends_on macos: :ventura', rendered)
        for declaration in MANIFEST.strip().splitlines():
            self.assertIn(declaration.strip().rstrip(","), rendered)
        self.assertIn(f'revision: "{"a" * 40}"', rendered)
        self.assertIn(f'revision: "{"b" * 40}"', rendered)
        self.assertEqual(rendered, release.rewrite_formula(rendered, MANIFEST, PINS, "2.2.1", "e" * 64))

    def test_notarization_requires_accepted_status(self):
        with tempfile.TemporaryDirectory() as temporary:
            path = Path(temporary)
            archive = path / "xcodes.zip"
            archive.touch()
            stub = path / "xcrun"
            stub.write_text('''#!/bin/sh
if [ "$2" = submit ]; then
    printf '{"status":"%s","id":"fixture-id"}\\n' "$TEST_NOTARY_STATUS"
else
    echo "notarization log for $3"
fi
''')
            stub.chmod(0o755)
            for status, success in (("Invalid", False), ("In Progress", False), ("Accepted", True)):
                with self.subTest(status=status):
                    result = subprocess.run(
                        [ROOT / "notarize.sh", archive, release.TEAM], capture_output=True, text=True,
                        env={**os.environ, "PATH": f"{path}:{os.environ['PATH']}", "TEST_NOTARY_STATUS": status},
                    )
                    self.assertEqual(result.returncode == 0, success, result.stderr)
                    if not success:
                        self.assertIn(f"Notarization status: {status}", result.stderr)

    def test_push_stops_when_main_moves(self):
        state = {"version": "2.2.1", "tag_sha": "wanted-tag", "base": "original-main"}
        with patch.object(release, "remote_refs", return_value={"refs/heads/main": "new-main"}):
            with patch.object(release, "git") as git:
                with self.assertRaisesRegex(release.ReleaseError, "CLI main changed"):
                    release.push_version(Path("/unused"), state)
                git.assert_not_called()

    def test_missing_draft_generates_notes_for_the_tagged_commit(self):
        state = {"version": "2.2.1", "previous": "2.2.0", "commit": "tagged-commit"}
        with patch.object(release, "github", side_effect=[{"body": "Generated notes"}, {"id": 1}]) as github:
            release.draft_release(Path("/unused"), state, [])
        generated, created = github.call_args_list
        self.assertEqual(generated.kwargs["body"], {
            "tag_name": "2.2.1", "previous_tag_name": "2.2.0", "target_commitish": "tagged-commit",
        })
        self.assertEqual(created.kwargs["body"]["body"], "Generated notes")
        self.assertTrue(created.kwargs["body"]["draft"])

    def test_uploaded_asset_with_wrong_digest_stops_publication(self):
        asset = {"name": "xcodes.zip", "state": "uploaded", "size": 123, "digest": "sha256:wrong"}
        with self.assertRaisesRegex(release.ReleaseError, "does not match"):
            release.verify_asset(asset, {"size": 123, "digest": "sha256:expected"})

    def test_release_preserves_draft_and_resumes_upload_and_tap_push(self):
        with tempfile.TemporaryDirectory() as temporary, contextlib.redirect_stdout(io.StringIO()):
            root = Path(temporary)
            repos = {repo: root / repo.split("/")[1] for repo in (release.CLI, release.TAP)}
            git_env = {
                **release.ENV, "GIT_AUTHOR_NAME": "Release Fixture", "GIT_AUTHOR_EMAIL": "fixture@example.invalid",
                "GIT_COMMITTER_NAME": "Release Fixture", "GIT_COMMITTER_EMAIL": "fixture@example.invalid",
                "GIT_CONFIG_GLOBAL": os.devnull, "GIT_CONFIG_SYSTEM": os.devnull,
            }
            with patch.object(release, "ENV", git_env), patch.object(release, "ROOT", root / "seed-xcodes"):
                self.exercise_release(root, repos)

    def exercise_release(self, root, repos):
        def seed(repo, files):
            destination = root / f"seed-{repos[repo].name}"
            destination.mkdir()
            release.git("init", "--quiet", "-b", "main", cwd=destination)
            for name, text in files.items():
                file = destination / name
                file.parent.mkdir(parents=True, exist_ok=True)
                file.write_text(text)
            release.git("add", ".", cwd=destination)
            release.git("commit", "--quiet", "-m", "Initial", cwd=destination)
            release.git("clone", "--bare", "--quiet", destination, repos[repo], cwd=destination)
            return release.git("rev-parse", "HEAD", cwd=destination).decode().strip()

        base = seed(release.CLI, {
            release.VERSION_FILE: 'public var version: Version {\n    Version("2.2.0")!\n}\n',
            "Scripts/release": "# release command fixture\n",
            "Package.swift": MANIFEST, "Package.resolved": PINS,
        })
        seed(release.TAP, {release.FORMULA: FORMULA})
        storage = root / "releases"
        storage.mkdir()
        path = storage / "2.2.1"
        draft = {"id": 1, "draft": True, "prerelease": False, "tag_name": "",
                 "body": "Customized release notes", "target_commitish": "main",
                 "author": {"login": "github-actions[bot]"}, "assets": [], "html_url": "fixture-release"}
        uploads = []
        tap_pushes = []

        def github(repo, endpoint="", *, method="GET", body=None, paginate=False):
            if (repo, endpoint) == (release.CLI, "/releases?per_page=100"):
                return [[draft.copy()]]
            if endpoint.startswith("/actions/"):
                return {"workflow_runs": [{"status": "completed"}]}
            if (repo, endpoint) == (release.CLI, "/releases/1"):
                if method == "PATCH":
                    draft.update(body)
                return draft.copy()
            if (repo, endpoint) == (release.CLI, "/releases/latest"):
                self.assertFalse(draft["draft"])
                return draft.copy()
            self.fail(f"Unexpected GitHub call {repo}{endpoint} ({method})")

        def remote_file(repo, name, ref):
            return release.git("show", f"{ref}:{name}", cwd=repos[repo]).decode()

        actual_run = release.run

        def run(*command, **options):
            if command[:2] == ("swift", "test"):
                (options["cwd"] / ".build").mkdir()
                return
            if command[:3] == ("gh", "release", "upload"):
                artifact = command[4]
                if len(uploads) == 1:
                    uploads.append("interrupted")
                    raise release.ReleaseError("upload interrupted")
                uploads.append(artifact.name)
                draft["assets"].append({"name": artifact.name, "state": "uploaded", **release.fingerprint(artifact)})
                return
            if command[0] == "curl":
                self.assertFalse(draft["draft"])
                shutil.copyfile(path / release.bottle_name("2.2.1"), command[-2])
                return
            if "push" in command and options["cwd"].name == "tap":
                tap_pushes.append(command)
                if len(tap_pushes) == 1:
                    raise release.ReleaseError("tap push interrupted")
            return actual_run(*command, **options)

        def make_artifacts(stage, source, version):
            self.assertIn(f'Version("{version}")!', (source / release.VERSION_FILE).read_text())
            names = ["xcodes.zip", *(release.bottle_name(version, platform) for platform in release.BOTTLE_PLATFORMS)]
            for name in names:
                (stage / name).write_text(f"Notarized artifact fixture {name}")
            return {name: release.fingerprint(stage / name) for name in names}

        with patch.object(release, "repo_url", side_effect=lambda repo: repos[repo].as_uri()):
            with patch.object(release, "github", side_effect=github), patch.object(release, "remote_file", side_effect=remote_file):
                with patch.object(release, "run", side_effect=run), patch.object(release, "make_artifacts", side_effect=make_artifacts):
                    state = {"version": "2.2.1", "previous": "2.2.0", "base": base}
                    release.prepare(path, state, FORMULA)
                    with self.assertRaisesRegex(release.ReleaseError, "upload interrupted"):
                        release.finish(path, state)
                    self.assertTrue(draft["draft"])
                    with self.assertRaisesRegex(release.ReleaseError, "tap push interrupted"):
                        release.finish(path, json.loads((path / "release.json").read_text()))
                    self.assertFalse(draft["draft"])
                    release.finish(path, json.loads((path / "release.json").read_text()))
                    self.assertEqual(draft["body"], "Customized release notes")
                    self.assertEqual(uploads.count("xcodes.zip"), 1)
                    self.assertEqual(len(draft["assets"]), len(state["artifacts"]))
                    self.assertEqual(len(tap_pushes), 2)
                    self.assertEqual(release.remote_refs(release.CLI, "refs/tags/2.2.1")["refs/tags/2.2.1"], state["tag_sha"])
                    formula = remote_file(release.TAP, release.FORMULA, "main")
                    self.assertIn('tag: "2.2.1"', formula)
                    self.assertIn(state["artifacts"][release.bottle_name("2.2.1")]["digest"][7:], formula)


if __name__ == "__main__":
    unittest.main()
