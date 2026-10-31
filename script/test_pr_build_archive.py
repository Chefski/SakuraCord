#!/usr/bin/env python3
import importlib.util
import json
import os
import plistlib
from unittest.mock import patch
from pathlib import Path
import stat
import struct
import tempfile
import unittest
import zipfile

spec = importlib.util.spec_from_file_location('archive', Path(__file__).with_name('pr_build_archive.py'))
module = importlib.util.module_from_spec(spec)
spec.loader.exec_module(module)


class ArchiveBoundaryTests(unittest.TestCase):
    def inspect(self, entries):
        with tempfile.TemporaryDirectory() as directory:
            path = Path(directory) / 'fixture.zip'
            with zipfile.ZipFile(path, 'w') as archive:
                for name, data, symlink in entries:
                    info = zipfile.ZipInfo(name)
                    info.external_attr = ((stat.S_IFLNK if symlink else stat.S_IFREG) | 0o644) << 16
                    archive.writestr(info, data)
            with module.inspect_zip(path):
                pass

    def test_rejects_archive_traversal_duplicate_paths_and_escaping_symlinks(self):
        for entries in [
            [('../escape', b'x', False)], [('/absolute', b'x', False)],
            [('a', b'x', False), ('a', b'y', False)],
            [('root/link', b'../../outside', True)],
            [('root/link', b'/outside', True)],
            [('root/a', b'b', True), ('root/b', b'a', True)],
            [('root/link', b'..', True), ('root/link/escape', b'x', False),
             ('escape', b'../outside', True)],
            [('SakuraCord.app/a', b'.', True),
             ('SakuraCord.app/b', b'a/../..', True),
             ('SakuraCord.app/b/escape', b'x', False)],
            [('SakuraCord.app/link', b'inside', True),
             ('SakuraCord.app/LINK/payload', b'x', False)],
            [('SakuraCord.app/Contents/Inner', b'..', True),
             ('SakuraCord.app/escape', b'Contents/Inner/../../outside', True)],
        ]:
            with self.subTest(entries=entries), self.assertRaises(ValueError):
                self.inspect(entries)

    def test_rejects_local_header_name_disagreeing_with_directory(self):
        with tempfile.TemporaryDirectory() as directory:
            path = Path(directory) / 'fixture.zip'
            with zipfile.ZipFile(path, 'w') as archive:
                archive.writestr('safe', b'x')
            data = path.read_bytes()
            path.write_bytes(data[:30] + b'../x' + data[34:])
            with self.assertRaises(zipfile.BadZipFile):
                module.inspect_zip(path)

    def test_rejects_alternate_unicode_path_in_central_or_local_extra(self):
        with tempfile.TemporaryDirectory() as directory:
            path = Path(directory) / 'fixture.zip'
            info = zipfile.ZipInfo('safe')
            alternate = b'\x01' + bytes(4) + b'../outside'
            info.extra = struct.pack('<HH', 0x7075, len(alternate)) + alternate
            with zipfile.ZipFile(path, 'w') as archive:
                archive.writestr(info, b'x')
            data = path.read_bytes()
            with self.assertRaisesRegex(ValueError, 'alternate Unicode'):
                module.inspect_zip(path)
            # Leave the forbidden field only in the local header.
            central = data.index(b'PK\x01\x02')
            central_extra = central + 46 + len('safe')
            local_only = data[:central_extra] + b'\x74\x70' + data[central_extra + 2:]
            path.write_bytes(local_only)
            with self.assertRaisesRegex(ValueError, 'alternate Unicode'):
                module.inspect_zip(path)
            # Leave it only in the central directory.
            local_extra = 30 + len('safe')
            path.write_bytes(data[:local_extra] + b'\x74\x70' + data[local_extra + 2:])
            with self.assertRaisesRegex(ValueError, 'alternate Unicode'):
                module.inspect_zip(path)

    def test_accepts_internal_framework_symlinks(self):
        self.inspect([('SakuraCord.app/Framework/Versions/A/binary', b'x', False),
                      ('SakuraCord.app/Framework/Versions/Current', b'A', True),
                      ('SakuraCord.app/Framework/binary', b'Versions/Current/binary', True)])

    def test_validates_exact_bundle_identity_and_matching_symbols(self):
        for name in ('SakuraCord Debug', 'SakuraCord'):
            with self.subTest(name=name):
                self.validate_bundle_identity(name)

    def validate_bundle_identity(self, name):
        bundle = f'{name}.app'
        context = dict(schemaVersion=1, id='pr-7-run-99-attempt-2', pullRequest=7,
                       headSHA='a' * 40, baseSHA='b' * 40, builtSHA='c' * 40,
                       runID=99, runAttempt=2, configuration='debug', architecture='arm64')
        info = dict(CFBundleIdentifier='dev.sakuracord.SakuraCord',
                    CFBundleExecutable=name, CFBundleVersion='4000000000000099002',
                    CFBundleShortVersionString='0.1.6', LSMinimumSystemVersion='27.0',
                    SakuraCordBuildConfiguration='debug', SakuraCordUpdatesEnabled=True,
                    SakuraCordReleaseTrack='nightly', SUAllowsVersionDowngrades=True,
                    SUScheduledCheckInterval=21600, SUAllowsAutomaticUpdates=True,
                    SakuraCordBuildSwitchingProtocol=1, SakuraCordPullRequestBuildID=context['id'],
                    SakuraCordPullRequestNumber=7, SakuraCordBuildHeadSHA=context['headSHA'],
                    SakuraCordBuildCommitSHA=context['builtSHA'], SakuraCordBuildRunID='99',
                    SakuraCordBuildRunAttempt=2, SUPublicEDKey='public-test-key',
                    SURequireSignedFeed=True, SUVerifyUpdateBeforeExtraction=True,
                    SUEnableAutomaticChecks=True, SUAutomaticallyUpdate=False,
                    SUEnableInstallerLauncherService=True,
                    SUFeedURL='https://github.com/SakuraCordApp/SakuraCord/releases/latest/download/appcast.xml',
                    SakuraCordNightlyFeedURL='https://sakuracord.app/updates/appcast.xml')
        header = struct.pack('<IIIIIIII', 0xfeedfacf, 0x100000c, 0, 2, 1, 24, 0, 0)
        executable = header + struct.pack('<II', 0x1b, 24) + bytes(range(16))
        with tempfile.TemporaryDirectory() as directory, patch.dict(os.environ, SPARKLE_ED_PUBLIC_KEY='public-test-key'):
            root = Path(directory)
            (root / 'build.json').write_text(json.dumps(context))
            def write_app(bundle=bundle, executable_name=name):
                with zipfile.ZipFile(root / 'SakuraCord.app.zip', 'w') as archive:
                    archive.writestr(f'{bundle}/Contents/Info.plist', plistlib.dumps(info))
                    archive.writestr(f'{bundle}/Contents/Resources/pr-build.json', json.dumps(context))
                    archive.writestr(f'{bundle}/Contents/MacOS/{executable_name}', executable)
                    archive.writestr(f'{bundle}/Contents/Frameworks/Sparkle.framework/Sparkle', b'fixture')
            def write_symbols(data):
                with zipfile.ZipFile(root / 'SakuraCord.dSYM.zip', 'w') as archive:
                    archive.writestr('SakuraCord.app.dSYM/Contents/Resources/DWARF/SakuraCord', data)
            write_app()
            write_symbols(executable)
            self.assertEqual(module.validate(root, context)['buildVersion'], '4000000000000099002')
            write_app(bundle='Other.app')
            with self.assertRaisesRegex(ValueError, 'unexpected app archive root'):
                module.validate(root, context)
            other = 'SakuraCord' if name == 'SakuraCord Debug' else 'SakuraCord Debug'
            write_app(bundle=f'{other}.app', executable_name=other)
            with self.assertRaisesRegex(ValueError, 'CFBundleExecutable'):
                module.validate(root, context)
            write_app()
            write_symbols(executable[:-1] + b'x')
            with self.assertRaisesRegex(ValueError, 'symbols do not match'):
                module.validate(root, context)
            write_symbols(executable)
            info['SakuraCordInsecureDebugCredentialsEnabled'] = True
            write_app()
            with self.assertRaisesRegex(ValueError, 'insecure credentials'):
                module.validate(root, context)
            info.pop('SakuraCordInsecureDebugCredentialsEnabled')
            info['SakuraCordPullRequestBuildID'] = 'different-build'
            write_app()
            with self.assertRaisesRegex(ValueError, 'SakuraCordPullRequestBuildID'):
                module.validate(root, context)

    def test_reads_macho_uuid_and_rejects_truncated_commands(self):
        uuid = bytes(range(16))
        header = struct.pack('<IIIIIIII', 0xfeedfacf, 0x100000c, 0, 2, 1, 24, 0, 0)
        executable = header + struct.pack('<II', 0x1b, 24) + uuid
        self.assertEqual(module.macho_uuids(executable), {'arm64': uuid.hex()})
        with self.assertRaises(ValueError):
            module.macho_uuids(executable[:-1])


if __name__ == '__main__':
    unittest.main()
