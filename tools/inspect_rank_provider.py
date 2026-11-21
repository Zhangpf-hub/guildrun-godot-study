"""Read the three documented rank-provider examples from Steam demo build 26551710."""

import argparse
import hashlib
import struct
from pathlib import Path

import pefile
from capstone import CS_ARCH_X86, CS_MODE_64, Cs
from capstone.x86_const import X86_OP_MEM, X86_REG_RIP


ASSEMBLY_SHA = "31856a31b2aae7c6ce8a5619999dcb9d2cc0d69c9a18bec2a32362b29532588d"
METADATA_SHA = "78f2cc8030b5eb316d9a33016e89063fa8cda6b78acca04a04f3ca667a289a59"
PROVIDER_RVA = 0x62E9D0
EXAMPLES = {
    137: [
        (0x9190, "OnAbilityCast trigger"),
        (0x91DF, "GainShardsAction amount"),
        (0x9236, "Owner's permanent tracking increment"),
    ],
    185: [
        (0xC670, "Interval in seconds"),
        (0xC6C3, "OnInterval trigger"),
        (0xC6D0, "AllEnemies target"),
        (0xC729, "Damage coefficient"),
        (0xC744, "MaxHealth source stat"),
    ],
    190: [
        (0xD52F, "Amount per current owner rank, deployed"),
        (0xD6BD, "Amount per current owner rank, reserve"),
    ],
}


def verified_bytes(path, expected):
    data = path.read_bytes()
    if hashlib.sha256(data).hexdigest() != expected:
        raise ValueError(f"{path.name} differs from the audited Steam build 26551710")
    return data


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("install", type=Path, help="Guildrun Demo installation directory")
    parser.add_argument("--id", type=int, choices=EXAMPLES)
    args = parser.parse_args()
    assembly = verified_bytes(args.install / "GameAssembly.dll", ASSEMBLY_SHA)
    metadata = verified_bytes(args.install / "Guildrun_Data/il2cpp_data/Metadata/global-metadata.dat", METADATA_SHA)
    _, _, strings, _, string_data, _ = struct.unpack_from("<6I", metadata)
    decoder = Cs(CS_ARCH_X86, CS_MODE_64)
    decoder.detail = True
    with pefile.PE(data=assembly, fast_load=True) as pe:
        for modifier in ([args.id] if args.id is not None else EXAMPLES):
            print(f"RankModifier {modifier}")
            for offset, meaning in EXAMPLES[modifier]:
                rva = PROVIDER_RVA + offset
                instruction = next(decoder.disasm(pe.get_data(rva, 15), rva, count=1))
                value = ""
                for operand in instruction.operands:
                    if operand.type == X86_OP_MEM and operand.mem.base == X86_REG_RIP:
                        address = instruction.address + instruction.size + operand.mem.disp
                        token, = struct.unpack("<Q", pe.get_data(address, 8))
                        if token >> 29 == 5:
                            index = (token & 0x1FFFFFFF) >> 1
                            size, start = struct.unpack_from("<II", metadata, strings + 8 * index)
                            literal = metadata[string_data + start:string_data + start + size].decode()
                            value = f"  literal={literal}"
                print(f"  +0x{offset:05x}  {instruction.mnemonic} {instruction.op_str}{value}  [{meaning}]")


if __name__ == "__main__":
    main()
