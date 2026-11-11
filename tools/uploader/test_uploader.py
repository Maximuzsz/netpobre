import unittest
from pathlib import Path

from netpobre_uploader import format_bytes, safe_subfolder


class UploaderHelpersTest(unittest.TestCase):
    def test_formats_file_sizes_for_people(self):
        self.assertEqual(format_bytes(1024), "1.0 KB")
        self.assertEqual(format_bytes(5 * 1024**3), "5.0 GB")

    def test_accepts_nested_library_folder(self):
        self.assertEqual(
            safe_subfolder(r"Ted Lasso\Temporada 03"),
            "Ted Lasso/Temporada 03",
        )

    def test_rejects_path_escape(self):
        with self.assertRaises(ValueError):
            safe_subfolder("../fora-da-biblioteca")


if __name__ == "__main__":
    unittest.main()
