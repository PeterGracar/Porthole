import XCTest

/// Fixtures below are verbatim outputs captured from MacPorts 2.12.5.
final class PortParserTests: XCTestCase {

    // MARK: - installed

    func testParseInstalled() {
        let output = """
          aom @3.13.1_2 (active)
          bash @5.3.9_0 (active)
          cairo @1.18.4_2+quartz+x11 (active)
          db48 @4.8.30_5 (active)
        """
        let ports = PortParser.parseInstalled(output)
        XCTAssertEqual(ports.count, 4)
        XCTAssertEqual(ports[0].name, "aom")
        XCTAssertEqual(ports[0].version, "3.13.1_2")
        XCTAssertTrue(ports[0].variants.isEmpty)
        XCTAssertTrue(ports[0].isActive)

        XCTAssertEqual(ports[2].name, "cairo")
        XCTAssertEqual(ports[2].version, "1.18.4_2")
        XCTAssertEqual(ports[2].variants, ["quartz", "x11"])
        XCTAssertEqual(ports[2].versionSpec, "@1.18.4_2+quartz+x11")
    }

    func testParseInstalledInactiveEntry() {
        let output = "  wget @1.24.5_0\n  wget @1.25.0_0 (active)\n"
        let ports = PortParser.parseInstalled(output)
        XCTAssertEqual(ports.count, 2)
        XCTAssertFalse(ports[0].isActive)
        XCTAssertTrue(ports[1].isActive)
        XCTAssertNotEqual(ports[0].id, ports[1].id)
    }

    func testParseInstalledSkipsNoise() {
        XCTAssertTrue(PortParser.parseInstalled("No ports are installed.\n").isEmpty)
        XCTAssertTrue(PortParser.parseInstalled("").isEmpty)
    }

    // MARK: - outdated

    func testParseOutdated() {
        let output = "wget                           1.24.5_0 < 1.25.0_0\n"
        let outdated = PortParser.parseOutdated(output)
        XCTAssertEqual(outdated.count, 1)
        XCTAssertEqual(outdated[0].name, "wget")
        XCTAssertEqual(outdated[0].detail, "1.24.5_0 < 1.25.0_0")
    }

    func testOutdatedVersionSplit() {
        let port = OutdatedPort(name: "wget", detail: "1.24.5_0 < 1.25.0_0")
        XCTAssertEqual(port.currentVersion, "1.24.5_0")
        XCTAssertEqual(port.newVersion, "1.25.0_0")

        let odd = OutdatedPort(name: "foo", detail: "platform darwin 24 != darwin 25")
        XCTAssertEqual(odd.currentVersion, "platform darwin 24 != darwin 25")
        XCTAssertEqual(odd.newVersion, "")
    }

    func testParseOutdatedEmpty() {
        XCTAssertTrue(PortParser.parseOutdated("").isEmpty)
        XCTAssertTrue(PortParser.parseOutdated("\n").isEmpty)
    }

    // MARK: - search

    func testParseSearch() {
        let output = "wget\t1.25.0\tnet www\tinternet file retriever\nwget2\t2.1.0\tnet\tsuccessor of wget\n"
        let results = PortParser.parseSearch(output)
        XCTAssertEqual(results.count, 2)
        XCTAssertEqual(results[0].name, "wget")
        XCTAssertEqual(results[0].version, "1.25.0")
        XCTAssertEqual(results[0].categories, "net www")
        XCTAssertEqual(results[0].summary, "internet file retriever")
    }

    func testParseSearchSkipsNoMatchLine() {
        XCTAssertTrue(PortParser.parseSearch("No match for *nosuchthing* found\n").isEmpty)
    }

    // MARK: - info

    func testParseInfo() {
        // port -q info --index --version --description --homepage --variants
        //   --license --categories --long_description wget
        let output = """
        1.25.0
        internet file retriever
        https://www.gnu.org/software/wget/
        debug, debugoptimized, quartz, x11, tests, universal
        GPL-3+
        net www
        GNU Wget is a free software package for retrieving files using HTTP and FTP.
        """
        let info = PortParser.parseInfo(output)
        XCTAssertNotNil(info)
        XCTAssertEqual(info?.version, "1.25.0")
        XCTAssertEqual(info?.summary, "internet file retriever")
        XCTAssertEqual(info?.homepage, "https://www.gnu.org/software/wget/")
        XCTAssertEqual(info?.variants, ["debug", "debugoptimized", "quartz", "x11", "tests", "universal"])
        XCTAssertEqual(info?.license, "GPL-3+")
        XCTAssertEqual(info?.categories, "net www")
        XCTAssertEqual(info?.longDescription, "GNU Wget is a free software package for retrieving files using HTTP and FTP.")
    }

    func testParseInfoEmpty() {
        XCTAssertNil(PortParser.parseInfo("\n"))
    }

    // MARK: - deps

    func testParseDeps() {
        let output = """
        Extract Dependencies: xz
        Build Dependencies: pkgconfig, python314, meson, ninja
        Library Dependencies: expat, fontconfig, freetype
        """
        let deps = PortParser.parseDeps(output)
        XCTAssertEqual(deps.count, 3)
        XCTAssertEqual(deps[0].kind, "Extract")
        XCTAssertEqual(deps[0].items, ["xz"])
        XCTAssertEqual(deps[1].items, ["pkgconfig", "python314", "meson", "ninja"])
        XCTAssertEqual(deps[2].kind, "Library")
    }

    // MARK: - echo lists

    func testParseEchoList() {
        let output = "  wget @1.24.5_0\n  cairo @1.18.2_0+quartz\n"
        XCTAssertEqual(PortParser.parseEchoList(output), ["wget @1.24.5_0", "cairo @1.18.2_0+quartz"])
        XCTAssertTrue(PortParser.parseEchoList("").isEmpty)
    }

    // MARK: - package token validation

    func testPackageTokenValidation() {
        XCTAssertTrue(PackageToken.isValid("wget"))
        XCTAssertTrue(PackageToken.isValid("libgcc-devel"))
        XCTAssertTrue(PackageToken.isValid("py314-setuptools"))
        XCTAssertTrue(PackageToken.isValid("@1.18.4_2+quartz+x11"))

        XCTAssertFalse(PackageToken.isValid(""))
        XCTAssertFalse(PackageToken.isValid("-Nselfupdate"))
        XCTAssertFalse(PackageToken.isValid("--follow-dependents"))
        XCTAssertFalse(PackageToken.isValid("@"))
        XCTAssertFalse(PackageToken.isValid("foo bar"))
        XCTAssertFalse(PackageToken.isValid("foo;rm"))
        XCTAssertFalse(PackageToken.isValid("$(evil)"))
    }

    func testSanitizedSearchTerm() {
        XCTAssertEqual(PackageToken.sanitizedSearchTerm("wget"), "wget")
        XCTAssertEqual(PackageToken.sanitizedSearchTerm("w*g?t"), "wgt")
        XCTAssertEqual(PackageToken.sanitizedSearchTerm("foo bar"), "foobar")
        XCTAssertEqual(PackageToken.sanitizedSearchTerm("'\";`"), "")
    }
}
