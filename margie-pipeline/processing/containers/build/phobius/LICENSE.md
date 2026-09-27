# phobius container — licensing

⚠️ **USER ACTION REQUIRED**: Phobius is **NOT** redistributable. The bundled `phobius101_linux.tgz` in this build directory was downloaded under an **academic** licence and **MUST NOT** be redistributed in any public image (including pushing to a public Docker Hub or GHCR registry). If you re-build and re-publish, **you must first delete the bundled tarball and require end users to download it themselves**.

## Summary

| Component | License | Bundled? | Redistribution | Commercial | User action? |
|---|---|---|---|---|---|
| Phobius 1.01 | **Academic only, NO redistribution** | ⚠️ in build context only — must NOT be pushed to public registry | ❌ forbidden | ❌ commercial licence required | ⚠️ **register and download yourself** |
| Perl + decodeanhmm runtime | Phobius bundle | ⚠️ same as above | ❌ | ❌ | n/a |
| Debian base | various | ✅ | ✅ | ✅ | none |

---

## 1. Phobius — Academic licence, no redistribution

**Upstream:** Stockholm Bioinformatics Center (SBC) / Lukas Käll
**Distribution:** https://phobius.sbc.su.se/data.html
**Citation:** Käll, L., Krogh, A., Sonnhammer, E.L.L. (2004) *A combined transmembrane topology and signal peptide prediction method.* J. Mol. Biol. 338(5):1027–1036.

### License notice (quoted from the Phobius download page, https://phobius.sbc.su.se/data.html):

> Phobius is available free of charge to academic users.
>
> Commercial users must contact us for a licence.
>
> You are NOT allowed to redistribute the program or to host it on another
> server. End users must download the software themselves from this page.

### Plain-language interpretation

- **Bundling in a public image is a licence violation.** This image's build context contains `phobius101_linux.tgz` only for local development; the file MUST be removed before publishing the image to any public registry.
- For private internal use within your own institution, after each user has individually accepted the SBC terms, bundling is tolerated. Confirm with your institution's research-software office.
- For peer-reviewed publication, the methods section should reference Phobius as a separately-installable dependency and document the version pin, NOT claim Phobius is included in the container.

## How to obtain Phobius

1. Visit https://phobius.sbc.su.se/data.html and read the licence.
2. Fill in the academic-user form (institution affiliation, email).
3. Download `phobius101_linux.tgz` from the link emailed to you.
4. Place the tarball in this build directory before running `build-phobius.sh` (for local use only).
5. For commercial use: contact Lukas Käll at lukas.kall@scilifelab.se.

## 2. Base image
Debian 12 slim. See https://www.debian.org/legal/licenses/.
