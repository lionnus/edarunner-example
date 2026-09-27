"""Count the DRC violations in a KLayout report database (.lyrdb), one per <item>."""

import xml.etree.ElementTree as ET


def count(path):
    return sum(1 for _ in ET.parse(path).getroot().iter("item"))
