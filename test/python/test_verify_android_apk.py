import tempfile
import unittest
import zipfile
from pathlib import Path
import sys

sys.path.insert(0, str(Path(__file__).resolve().parents[2] / 'scripts'))
from verify_android_apk import check_apk


class ApkVerificationTests(unittest.TestCase):
    def setUp(self):
        self.temp = tempfile.TemporaryDirectory()
        self.addCleanup(self.temp.cleanup)
        self.apk = Path(self.temp.name) / 'test.apk'

    def create(self, shadow=False, include_awg=True, other_abi=False):
        with zipfile.ZipFile(self.apk, 'w') as out:
            out.writestr('lib/arm64-v8a/libflutter.so', b'\x7fELF' + b'x' * 1024)
            if other_abi:
                out.writestr('lib/x86_64/libflutter.so', b'\x7fELF')
            if shadow:
                for name in ('libxray.so', 'libsingbox.so', 'libawg.so'):
                    if include_awg or name != 'libawg.so':
                        out.writestr('lib/arm64-v8a/' + name, b'\x7fELF' + b'x' * 1024)
                for name in ('geoip.dat', 'geosite.dat'):
                    out.writestr('assets/preload/' + name, b'x' * 2048)

    def test_original_without_preloaded_components(self):
        self.create()
        self.assertEqual([], check_apk(self.apk, 'arm64-v8a', 'original'))

    def test_shadow_complete(self):
        self.create(shadow=True)
        self.assertEqual([], check_apk(self.apk, 'arm64-v8a', 'shadow'))

    def test_shadow_rejects_missing_core(self):
        self.create(shadow=True, include_awg=False)
        self.assertTrue(any('libawg.so' in x for x in check_apk(self.apk, 'arm64-v8a', 'shadow')))

    def test_rejects_foreign_abi(self):
        self.create(other_abi=True)
        self.assertTrue(any('unexpected ABI' in x for x in check_apk(self.apk, 'arm64-v8a', 'original')))

    def test_original_rejects_shadow_payload(self):
        self.create(shadow=True)
        self.assertTrue(check_apk(self.apk, 'arm64-v8a', 'original'))


if __name__ == '__main__':
    unittest.main()
