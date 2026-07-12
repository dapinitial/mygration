import Foundation

/// Catalog of local dev services (web/db stacks). Like the agent catalog, this
/// maps where each service keeps config vs. data. The key distinction: config
/// files TRAVEL, database data must be DUMPED (never copy raw data dirs across
/// versions/arches), and daemons are REINSTALLED natively via brew.
public struct ServiceTool: Codable, Equatable, Identifiable {
    public var id: String
    public var name: String
    public var configPaths: [String]   // absolute or ~-relative; travel as config
    public var dataPaths: [String]     // raw data dirs — DUMP, don't copy
    public var dumpHint: String?       // how to export the data portably
    public var brewFormula: String?    // reinstall the daemon natively

    public init(id: String, name: String, configPaths: [String], dataPaths: [String] = [],
                dumpHint: String? = nil, brewFormula: String? = nil) {
        self.id = id; self.name = name; self.configPaths = configPaths
        self.dataPaths = dataPaths; self.dumpHint = dumpHint; self.brewFormula = brewFormula
    }
}

public enum ServiceCatalog {
    // note: brew prefix differs by arch (/usr/local intel, /opt/homebrew arm) —
    // both are probed. "$B" is expanded to each existing brew prefix at scan time.
    public static let all: [ServiceTool] = [
        ServiceTool(id: "apache", name: "Apache httpd",
                    configPaths: ["/etc/apache2/httpd.conf", "/etc/apache2/other",
                                  "$B/etc/httpd/httpd.conf", "~/Sites"],
                    brewFormula: "httpd"),
        ServiceTool(id: "nginx", name: "nginx",
                    configPaths: ["$B/etc/nginx/nginx.conf", "$B/etc/nginx/servers"],
                    brewFormula: "nginx"),
        ServiceTool(id: "php", name: "PHP",
                    configPaths: ["/etc/php.ini", "$B/etc/php"],
                    brewFormula: "php"),
        ServiceTool(id: "mysql", name: "MySQL / MariaDB",
                    configPaths: ["$B/etc/my.cnf", "/etc/my.cnf"],
                    dataPaths: ["$B/var/mysql"],
                    dumpHint: "mysqldump --all-databases > all.sql  (restore: mysql < all.sql)",
                    brewFormula: "mysql"),
        ServiceTool(id: "postgres", name: "PostgreSQL",
                    configPaths: ["$B/var/postgres/postgresql.conf", "$B/var/postgresql@*/postgresql.conf"],
                    dataPaths: ["$B/var/postgres", "$B/var/postgresql@*"],
                    dumpHint: "pg_dumpall > all.sql  (restore: psql -f all.sql)",
                    brewFormula: "postgresql"),
        ServiceTool(id: "redis", name: "Redis",
                    configPaths: ["$B/etc/redis.conf"],
                    dataPaths: ["$B/var/db/redis"],
                    dumpHint: "redis-cli SAVE  → copy dump.rdb (usually just re-warm the cache)",
                    brewFormula: "redis"),
        ServiceTool(id: "valet", name: "Laravel Valet",
                    configPaths: ["~/.config/valet"], brewFormula: "composer"),
        ServiceTool(id: "dnsmasq", name: "dnsmasq",
                    configPaths: ["$B/etc/dnsmasq.conf", "$B/etc/dnsmasq.d"],
                    brewFormula: "dnsmasq"),
        ServiceTool(id: "mamp", name: "MAMP",
                    configPaths: ["/Applications/MAMP/conf"],
                    dataPaths: ["/Applications/MAMP/db"],
                    dumpHint: "export DBs from MAMP's phpMyAdmin, or mysqldump the MAMP socket"),
        ServiceTool(id: "hosts", name: "Custom /etc/hosts entries",
                    configPaths: ["/etc/hosts"]),
    ]
}

public struct DiscoveredService: Codable, Equatable, Identifiable {
    public var id: String
    public var name: String
    public var configFound: [String]
    public var dataFound: [String]     // present → needs a dump before migration
    public var dumpHint: String?
    public var brewFormula: String?
}
