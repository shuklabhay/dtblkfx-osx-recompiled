#!/usr/bin/env python3
"""Build reproducible VST3 and Ableton preset archives from validated states."""

from __future__ import annotations

import argparse
import copy
import gzip
import io
import struct
import xml.etree.ElementTree as ET
import zipfile
from pathlib import Path


FIXED_ZIP_TIME = (1980, 1, 1, 0, 0, 0)


def write_gzip(path: Path, data: bytes) -> None:
    """Write deterministic gzip data."""
    output = io.BytesIO()
    with gzip.GzipFile(filename="", mode="wb", fileobj=output, mtime=0) as stream:
        stream.write(data)
    path.parent.mkdir(parents=True, exist_ok=True)
    path.write_bytes(output.getvalue())


def find_dtblk_device(root: ET.Element) -> ET.Element:
    """Find the DtBlkFx VST3 device in a Live document."""
    for device in root.iter("PluginDevice"):
        name = device.find("./PluginDesc/Vst3PluginInfo/Name")
        if name is not None and name.get("Value") == "DtBlkFx":
            return device
    raise ValueError("Live document contains no DtBlkFx VST3 device")


def capture_template(live_set: Path, output: Path) -> None:
    """Extract and scrub a Live-authored DtBlkFx device template."""
    with gzip.open(live_set, "rb") as stream:
        document = ET.fromstring(stream.read())
    device = copy.deepcopy(find_dtblk_device(document))
    device.set("Id", "0")
    for tag in (
        "AutomationTarget",
        "ModulationTarget",
        "Pointee",
        "Vst3PluginInfo",
        "Vst3Preset",
    ):
        for element in device.iter(tag):
            if "Id" in element.attrib:
                element.set("Id", "0")
    for container_path in ("./LastPresetRef/Value", "./SourceContext/Value"):
        container = device.find(container_path)
        if container is not None:
            container.clear()
    user_name = device.find("UserName")
    if user_name is not None:
        user_name.set("Value", "")
    for parameter in device.findall("./ParameterList/PluginFloatParameter"):
        name = parameter.find("ParameterName")
        if name is not None:
            name.set("Value", "")
        user_range = parameter.find("LastUserRange")
        if user_range is not None:
            first = user_range.find("First")
            last = user_range.find("Last")
            if first is not None:
                first.set("Value", "Invalid")
            if last is not None:
                last.set("Value", "Invalid")
    root = ET.Element(
        "Ableton",
        {
            "MajorVersion": document.get("MajorVersion", "5"),
            "MinorVersion": document.get("MinorVersion", "11.0_11300"),
            "SchemaChangeCount": document.get("SchemaChangeCount", "17"),
            "Creator": document.get("Creator", "Ableton Live 11"),
            "Revision": document.get("Revision", ""),
        },
    )
    root.append(device)
    ET.indent(root, space="\t")
    xml = b'<?xml version="1.0" encoding="UTF-8"?>\n' + ET.tostring(root, encoding="utf-8")
    write_gzip(output, xml)


def preset_chunks(path: Path) -> dict[bytes, bytes]:
    """Read chunks from one canonical VST3 preset file."""
    data = path.read_bytes()
    if len(data) < 48 or data[:4] != b"VST3":
        raise ValueError(f"invalid VST3 preset: {path}")
    list_offset = struct.unpack_from("<Q", data, 40)[0]
    if data[list_offset : list_offset + 4] != b"List":
        raise ValueError(f"missing VST3 chunk list: {path}")
    count = struct.unpack_from("<I", data, list_offset + 4)[0]
    chunks: dict[bytes, bytes] = {}
    offset = list_offset + 8
    for _ in range(count):
        chunk_id = data[offset : offset + 4]
        chunk_offset, chunk_size = struct.unpack_from("<QQ", data, offset + 4)
        chunks[chunk_id] = data[chunk_offset : chunk_offset + chunk_size]
        offset += 20
    return chunks


def preset_name(path: Path) -> str:
    """Recover the factory name from a numbered preset filename."""
    stem = path.stem
    return stem[3:] if len(stem) > 3 and stem[:2].isdigit() and stem[2] == " " else stem


def make_ableton_preset(template: bytes, vstpreset: Path) -> bytes:
    """Embed one validated VST3 component state in a Live device preset."""
    root = ET.fromstring(gzip.decompress(template))
    chunks = preset_chunks(vstpreset)
    component = chunks.get(b"Comp")
    if component is None:
        raise ValueError(f"VST3 preset has no component state: {vstpreset}")
    processor_state = root.find("./PluginDevice/PluginDesc/Vst3PluginInfo/Preset/Vst3Preset/ProcessorState")
    if processor_state is None:
        raise ValueError("Ableton template has no processor state")
    processor_state.text = component.hex().upper()
    name = preset_name(vstpreset)
    preset_name_node = root.find("./PluginDevice/PluginDesc/Vst3PluginInfo/Preset/Vst3Preset/Name")
    user_name = root.find("./PluginDevice/UserName")
    if preset_name_node is not None:
        preset_name_node.set("Value", name)
    if user_name is not None:
        user_name.set("Value", name)
    ET.indent(root, space="\t")
    xml = b'<?xml version="1.0" encoding="UTF-8"?>\n' + ET.tostring(root, encoding="utf-8")
    output = io.BytesIO()
    with gzip.GzipFile(filename="", mode="wb", fileobj=output, mtime=0) as stream:
        stream.write(xml)
    return output.getvalue()


def add_zip_file(archive: zipfile.ZipFile, name: str, data: bytes) -> None:
    """Add one deterministic regular file to a ZIP archive."""
    info = zipfile.ZipInfo(name, FIXED_ZIP_TIME)
    info.compress_type = zipfile.ZIP_DEFLATED
    info.external_attr = 0o100644 << 16
    archive.writestr(info, data)


def build_archives(vst3_directory: Path, template_path: Path, output_directory: Path) -> None:
    """Build and self-validate the portable preset archives."""
    vstpresets = sorted(vst3_directory.glob("*.vstpreset"))
    if len(vstpresets) != 43:
        raise ValueError(f"expected 43 VST3 presets, found {len(vstpresets)}")
    template = template_path.read_bytes()
    output_directory.mkdir(parents=True, exist_ok=True)
    vst3_zip = output_directory / "DtBlkFx-VST3-Presets.zip"
    ableton_zip = output_directory / "DtBlkFx-Ableton-Live-Presets.zip"

    vst3_readme = (
        "DtBlkFx VST3 factory presets\n\n"
        "macOS: copy the 'VST3 Presets' folder to ~/Library/Audio/Presets/.\n"
        "The files use Steinberg's standard .vstpreset component/controller state format.\n"
    ).encode()
    ableton_readme = (
        "DtBlkFx presets for Ableton Live 11\n\n"
        "Copy the DtBlkFx folder into your Ableton User Library, then select User Library\n"
        "in Live's Browser. Each .adv contains the matching validated VST3 component state.\n"
    ).encode()

    with zipfile.ZipFile(vst3_zip, "w") as archive:
        add_zip_file(archive, "README.txt", vst3_readme)
        for preset in vstpresets:
            add_zip_file(
                archive,
                f"VST3 Presets/Darrell Tam/DtBlkFx/{preset.name}",
                preset.read_bytes(),
            )

    with zipfile.ZipFile(ableton_zip, "w") as archive:
        add_zip_file(archive, "README.txt", ableton_readme)
        for preset in vstpresets:
            data = make_ableton_preset(template, preset)
            root = ET.fromstring(gzip.decompress(data))
            processor_state = root.find(
                "./PluginDevice/PluginDesc/Vst3PluginInfo/Preset/Vst3Preset/ProcessorState"
            )
            expected = preset_chunks(preset)[b"Comp"]
            if processor_state is None or bytes.fromhex(processor_state.text or "") != expected:
                raise ValueError(f"Ableton state validation failed: {preset}")
            add_zip_file(archive, f"DtBlkFx/{preset.with_suffix('.adv').name}", data)

    for archive_path in (vst3_zip, ableton_zip):
        with zipfile.ZipFile(archive_path) as archive:
            if archive.testzip() is not None:
                raise ValueError(f"ZIP integrity failure: {archive_path}")
    print("PASS: packaged 43 VST3 and 43 Ableton presets")


def main() -> None:
    """Run template capture or archive generation."""
    parser = argparse.ArgumentParser()
    subparsers = parser.add_subparsers(dest="command", required=True)
    capture = subparsers.add_parser("capture-template")
    capture.add_argument("live_set", type=Path)
    capture.add_argument("output", type=Path)
    package = subparsers.add_parser("package")
    package.add_argument("vst3_directory", type=Path)
    package.add_argument("template", type=Path)
    package.add_argument("output_directory", type=Path)
    arguments = parser.parse_args()
    if arguments.command == "capture-template":
        capture_template(arguments.live_set, arguments.output)
    else:
        build_archives(arguments.vst3_directory, arguments.template, arguments.output_directory)


if __name__ == "__main__":
    main()
