package;

import haxe.Http;
import haxe.Json;
import haxe.io.Path;
import haxe.zip.Reader;
import sys.FileSystem;
import sys.io.File;

using StringTools;

class Main {

    static var platform:String;

    static var platformArchSuffix:String;

    static var cwd:String;

    static var argv:Array<String>;

    static var ceramicPath:String;

    static var ceramicToolsPath:String;

    static var ceramicZipPath:String;

    static var ceramicPackagePath:String;

    static var ceramicGitHeadPath:String;

    public static function main():Void {

        argv = [].concat(Sys.args());
        cwd = argv.pop();

        var customCwd = extractArgValue(argv, 'cwd');
        if (customCwd != null) {
            if (!Path.isAbsolute(customCwd)) {
                customCwd = Path.normalize(Path.join([cwd, customCwd]));
            }
            cwd = customCwd;
        }

        if (cwd == null) {
            cwd = Sys.getCwd();
        }

        platform = switch Sys.systemName() {
            default: null;
            case null: null;
            case "Windows": 'windows';
            case "Mac": 'mac';
            case "Linux": 'linux';
        }

        if (platform == null) {
            fail('Invalid platform.');
        }

        // Determine platform with architecture suffix
        platformArchSuffix = platform;
        var targetTag = extractArgValue(argv, 'version');
        if (platform == 'linux' && (targetTag == null || (!targetTag.startsWith('1') && !targetTag.startsWith('v1')))) {
            var arch = getLinuxArchitecture();
            if (arch == 'arm64' || arch == 'aarch64') {
                platformArchSuffix = 'linux-arm64';
            } else {
                platformArchSuffix = 'linux-x86_64';
            }
        }

        var commandName:String = null;
        if (argv.length > 0 && !argv[0].startsWith('-'))
            commandName = argv[0];

        var env = Sys.environment();

        // Check if ceramic is installed globally
        ceramicPath = resolveCeramicPath();

        // In case no ceramic was detected, check root/home directory
        if (ceramicPath == null) {
            if (customCwd == null) {
                if (platform == 'windows' && env.exists('USERPROFILE')) {
                    cwd = env.get('USERPROFILE');
                }
                else if (env.exists('HOME')) {
                    cwd = env.get('HOME');
                }
            }
            ceramicPath = Path.join([cwd, 'ceramic']);
        }


        ceramicZipPath = Path.join([cwd, 'ceramic-$platformArchSuffix.zip']);
        ceramicToolsPath = Path.join([ceramicPath, 'tools']);
        ceramicPackagePath = Path.join([ceramicPath, 'tools', 'package.json']);
        ceramicGitHeadPath = Path.join([ceramicPath, '.git', 'HEAD']);

        switch commandName {
            default:
                if (FileSystem.exists(ceramicPackagePath)) {
                    runCeramic(cwd, argv);
                }
                else {
                    fail('Unknown command $commandName');
                }
            case null:
                if (FileSystem.exists(ceramicPackagePath)) {
                    runCeramic(cwd, argv);
                }
                else {
                    print('ceramic is not installed globally or in current directory ($cwd)');
                    print('  To install it, run: haxelib run ceramic setup');
                }
            case 'setup':
                if (FileSystem.exists(ceramicGitHeadPath)) {
                    print('');
                    print('Your current installation of ceramic is managed via GIT');
                    print('path: $ceramicPath');
                    print('It cannot be updated via `haxelib run ceramic setup`.');
                    print('');
                    print('What you can do:');
                    print('');
                    print(' - Update your ceramic installation via GIT');
                    print('');
                    print(' - OR run `haxelib run ceramic setup --cwd \'some/custom/directory\'`');
                    print('   to install ceramic somewhere else');
                    print('');
                    print(' - OR run `ceramic unlink` to disable your current global ceramic');
                    print('   installation, then try to run this tool again');
                    print('');
                }
                else {
                    setup();
                }
        }

    }

    static function getLinuxArchitecture():String {
        try {
            var process = new sys.io.Process('uname', ['-m']);
            var output = process.stdout.readAll().toString().trim();
            process.close();
            return output;
        }
        catch (e:Dynamic) {
            // Default to x86_64 if we can't determine
            return 'x86_64';
        }
    }

    static function setup():Void {

        var releaseInfo:Dynamic = resolveLatestRelease();

        var targetTag = extractArgValue(argv, 'version');

        if (targetTag == null) {
            targetTag = releaseInfo.tag_name;
        }
        else if (!targetTag.startsWith('v')) {
            targetTag = 'v' + targetTag;
            try {
                var explicitReleaseInfo = Json.parse(requestUrl('https://api.github.com/repos/ceramic-engine/ceramic/releases/tags/$targetTag'));
                print('Resolved version tag: ${explicitReleaseInfo.tag_name}');
            }
            catch (e:Dynamic) {
                fail('Did not find ceramic version tag: $targetTag');
            }
        }

        var confirmed = false;

        var installedVersion:String = null;
        if (FileSystem.exists(ceramicPath)) {
            try {
                installedVersion = Json.parse(File.getContent(Path.join([ceramicPath, 'tools', 'package.json']))).version;
            }
            catch (e:Dynamic) {
                error('Failed to resolve installed ceramic version');
            }
        }

        if (installedVersion != null) {
            print('Detected existing ceramic version v$installedVersion ($ceramicPath)');
        }
        else {
            print('ceramic is not installed. It will be installed to: $ceramicPath');
        }

        var msg:String;
        if (installedVersion == null) {
            msg = 'Install ceramic $targetTag? (y/n)';
        }
        else if ('v' + installedVersion != targetTag) {
            msg = 'Update ceramic to $targetTag? (y/n)';
        }
        else {
            msg = 'Reinstall ceramic $targetTag? (y/n)';
        }

        if (installedVersion != null) {
            print('Please make sure Ceramic is not used when installing and Visual Studio Code is closed!');
        }

        if (extractArgFlag(argv, 'install')) {
            confirmed = true;
            print(msg);
            print('y');
        }
        else {
            confirmed = confirm(msg);
        }

        if (confirmed) {

            // Delete any existing zip
            if (FileSystem.exists(ceramicZipPath)) {
                deleteRecursive(ceramicZipPath);
            }

            // Download
            downloadFile('https://github.com/ceramic-engine/ceramic/releases/download/$targetTag/ceramic-$platformArchSuffix.zip', ceramicZipPath);

            // Delete any existing ceramic installation
            if (FileSystem.exists(ceramicPath)) {
                deleteRecursive(ceramicPath);
            }

            // Extract files
            unzipFile(ceramicZipPath, ceramicPath);

            msg = 'Make `ceramic` command available globally? (y/n)';
            var confirmLink = false;
            if (extractArgFlag(argv, 'global')) {
                confirmLink = true;
                print(msg);
                print('y');
            }
            else if (extractArgFlag(argv, 'local')) {
                confirmLink = false;
                print(msg);
                print('n');
            }
            else {
                confirmLink = confirm(msg);
            }
            if (confirmLink) {
                if (platform == 'windows')
                    runCeramic(ceramicPath, ['link']);
                else {
                    runCeramic(ceramicPath, ['link'], true);
                }
            }
            runCeramic(ceramicPath, ['help']);
        }

    }

    static function requestUrl(url:String):Null<String> {
        var h = new Http(url);
        h.setHeader('User-Agent', 'request');
        h.onError = err -> {
            throw 'Http error: ' + err;
        };
        h.request();
        return h.responseData;
    }

    static function resolveLatestRelease():Dynamic {

        var releases:Array<Dynamic> = Json.parse(requestUrl('https://api.github.com/repos/ceramic-engine/ceramic/releases'));

        for (release in releases) {
            if (release.assets != null) {
                var assets:Array<Dynamic> = release.assets;
                for (asset in assets) {
                    if (asset.name == 'ceramic-$platformArchSuffix.zip') {
                        return release;
                    }
                }
            }
        }

        fail('Failed to resolve latest ceramic version! Try again later?');
        return null;

    }

    static function resolveCeramicPath():String {

        var output = '';

        try {
            var process = new sys.io.Process('ceramic', ['path']);
            output += process.stdout.readAll().toString().trim();
            process.close();
        }
        catch (e:Dynamic) {}

        if (output.length == 0) {
            try {
                var process = new sys.io.Process('ceramic.cmd', ['path']);
                output += process.stdout.readAll().toString().trim();
                process.close();
            }
            catch (e:Dynamic) {}
        }

        if (output.length > 0 && FileSystem.exists(Path.join([output, 'package.json']))) {
            try {
                var packageJson = Json.parse(File.getContent(Path.join([output, 'package.json'])));
                if (packageJson.name == 'ceramic-tools' || packageJson.name == 'ceramic') {
                    return Path.directory(output);
                }
            }
            catch (e:Dynamic) {}
        }

        return null;

    }

    static function runCeramic(cwd:String, args:Array<String>, sudo:Bool = false):Void {

        var args = [].concat(args);

        var customCwd = extractArgValue(args, 'cwd');
        if (customCwd == null) {
            args.push('--cwd');
            args.push(cwd);
        }

        if (args.length == 2) {
            args = ['help'].concat(args);
        }

        var prevCwd = Sys.getCwd();
        Sys.setCwd(ceramicToolsPath);
        if (Sys.systemName() == 'Windows') {
            Sys.command('./ceramic.cmd', args);
        }
        else {
            if (sudo) {
                Sys.command('sudo', ['./ceramic'].concat(args));
            }
            else {
                Sys.command('./ceramic', args);
            }
        }
        Sys.setCwd(prevCwd);

    }

    static function downloadFile(remotePath:String, localPath:String = "", followingLocation:Bool = false):Void {
        if (localPath == "") {
            localPath = Path.withoutDirectory(remotePath);
        }
        if (!Path.isAbsolute(localPath)) {
            localPath = Path.join([cwd, localPath]);
        }

        var out = File.write(localPath, true);
        var progress = new Progress(out);
        var h = new Http(remotePath);

        h.cnxTimeout = 30;

        h.onError = function(e) {
            progress.close();
            FileSystem.deleteFile(localPath);
            throw e;
        };

        if (!followingLocation) {
            print("Downloading " + Path.withoutDirectory(remotePath) + "...");
        }

        h.customRequest(false, progress);

        if (h.responseHeaders != null && (h.responseHeaders.exists("Location") || h.responseHeaders.exists("location"))) {
            var location = h.responseHeaders.get("Location");
            if (location == null)
                location = h.responseHeaders.get("location");

            if (location != remotePath) {
                downloadFile(location, localPath, true);
            }
        }
    }

    static function unzipFile(source:String, targetPath:String):Void {

        print('Unzipping... (this may take a while)');

        if (platform == 'mac' || platform == 'linux') {

            var prevCwd = Sys.getCwd();
            Sys.setCwd(cwd);
            Sys.command('unzip', ['-q', source, '-d', targetPath]);
            Sys.setCwd(prevCwd);

        }
        else if (platform == 'windows') {

            var file = File.read(source, true);
            var entries = Reader.readZip(file);
            file.close();

            var numFiles = 0;

            for (entry in entries) {
                var fileName = entry.fileName;

                if (fileName.charAt(0) != "/" && fileName.charAt(0) != "\\" && fileName.split("..").length <= 1) {
                    var dirs = ~/[\/\\]/g.split(fileName);

                    var path = "";
                    var file = dirs.pop();

                    for (d in dirs) {
                        path += d;
                        FileSystem.createDirectory(targetPath + "/" + path);
                        path += "/";
                    }

                    if (file == "") {
                        continue; // Was just a directory
                    }

                    path += file;

                    //print("Extract " + path);

                    var data = Reader.unzip(entry);
                    var f = File.write(targetPath + "/" + path, true);

                    f.write(data);
                    f.close();
                }
            }

        }
        else {

            throw "Unzip on platform " + platform + " not supported";
        }

        print("Done");

    }

    static function untarGzFile(source:String, targetPath:String):Void {

        print('Unpacking... (this may take a while)');

        if (platform == 'mac' || platform == 'linux') {

            var prevCwd = Sys.getCwd();
            Sys.setCwd(cwd);
            Sys.command('tar', ['-xzf', source, '-C', targetPath]);
            Sys.setCwd(prevCwd);

        }
        else {

            throw "Untar on platform " + platform + " not supported";
        }

    }

    static function deleteRecursive(toDelete:String):Void {

        if (!FileSystem.exists(toDelete)) return;

        if (FileSystem.isDirectory(toDelete)) {

            for (name in FileSystem.readDirectory(toDelete)) {

                var path = Path.join([toDelete, name]);
                if (FileSystem.exists(path)) {
                    if (FileSystem.isDirectory(path)) {
                        deleteRecursive(path);
                    } else {
                        FileSystem.deleteFile(path);
                    }
                }
                else {
                    // Could happen if the file is a symlink
                    FileSystem.deleteFile(path);
                }
            }

            try {
                FileSystem.deleteDirectory(toDelete);
            }
            catch (e:Dynamic) {
                // Could happen if the file is a symlink
                FileSystem.deleteFile(toDelete);
            }

        }
        else {

            FileSystem.deleteFile(toDelete);

        }

    }

    static function confirm(question:String):Bool {

		while (true) {

            print(question);

            try
            {
                var x = Sys.stdin().readLine().trim().toLowerCase();
                if (x == 'y') {
                    return true;
                }
                else if (x == 'n') {
                    return false;
                }
            }
            catch (e:Dynamic)
            {
                Sys.exit(1);
            }
        }

        return false;

    }

    static function print(message:String):Void {

        Sys.println(message);

    }

    static function error(message:String):Void {

        Sys.println(message);

    }

    static function fail(message:String):Void {

        error(message);
        Sys.exit(1);

    }

    static function extractArgValue(args:Array<String>, name:String, remove:Bool = false):String {

        var index = args.indexOf('--$name');

        if (index == -1) {
            return null;
        }

        if (index + 1 >= args.length) {
            fail('A value is required after --$name argument.');
        }

        var value = args[index + 1];

        if (remove) {
            args.splice(index, 2);
        }

        return value;

    }

    static function extractArgFlag(args:Array<String>, name:String, remove:Bool = false):Bool {

        var index = args.indexOf('--$name');

        if (index == -1) {
            return false;
        }

        if (remove) {
            args.splice(index, 1);
        }

        return true;

    }

}

class Progress extends haxe.io.Output {
    var o:haxe.io.Output;
    var cur:Int;
    var max:Null<Int>;
    var start:Float;

    public function new(o) {
        this.o = o;
        cur = 0;
        start = haxe.Timer.stamp();
    }

    function bytes(n) {
        cur += n;
        if (max == null)
            Sys.print(cur + " bytes\r");
        else
            Sys.print(cur + "/" + max + " (" + Std.int((cur * 100.0) / max) + "%)\r");
    }

    public override function writeByte(c) {
        o.writeByte(c);
        bytes(1);
    }

    public override function writeBytes(s, p, l) {
        var r = o.writeBytes(s, p, l);
        bytes(r);
        return r;
    }

    public override function close() {
        super.close();
        o.close();
        var time = haxe.Timer.stamp() - start;
        var speed = (cur / time) / 1024;
        time = Std.int(time * 10) / 10;
        speed = Std.int(speed * 10) / 10;

        // When the path is a redirect, we don't want to display that the download completed

        if (cur > 400) {
            Sys.print("Download complete : " + cur + " bytes in " + time + "s (" + speed + "KB/s)\n");
        }
    }

    public override function prepare(m:Int) {
        max = m;
    }

}