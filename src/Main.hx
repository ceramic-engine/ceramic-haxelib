package;

import haxe.Json;
import com.akifox.asynchttp.HttpResponse;
import com.akifox.asynchttp.HttpRequest;
import haxe.Http;
import haxe.zip.Reader;
import haxe.io.Path;
import sys.FileSystem;
import sys.io.File;

using StringTools;

class Main {

    static var platform:String;

    static var cwd:String;

    static var argv:Array<String>;

    static var ceramicPath:String;

    static var ceramicToolsPath:String;

    static var ceramicZipPath:String;

    static var ceramicPackagePath:String;

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

        platform = switch Sys.systemName() {
            default: null;
            case null: null;
            case "Windows": 'windows';
            case "Mac": 'mac';
            case "Linux": 'linux';
        }

        var ceramicDir = cwd;

        if (platform == null) {
            fail('Invalid platform.');
        }

        var commandName:String = null;
        if (argv.length > 0 && !argv[0].startsWith('-'))
            commandName = argv[0];

        // When simply trying to run ceramic, check parent directories
        if (customCwd == null && commandName != 'setup') {
            ceramicDir = resolveCeramicParentDir(cwd);
        }

        ceramicZipPath = Path.join([ceramicDir, 'ceramic-$platform.zip']);
        ceramicPath = Path.join([ceramicDir, 'ceramic']);
        ceramicToolsPath = Path.join([ceramicPath, 'tools']);
        ceramicPackagePath = Path.join([ceramicPath, 'tools', 'package.json']);

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
                    print('ceramic is not installed in current directory ($cwd)');
                    print('  To install it, run: haxelib run ceramic setup');
                }
            case 'setup':
                setup();
        }

    }

    static function setup():Void {

        var releaseInfo = Json.parse(requestUrl('https://api.github.com/repos/ceramic-engine/ceramic/releases/latest'));

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
        
        if (installedVersion == null) {
            confirmed = confirm('Install ceramic $targetTag? (y/n)');
        }
        else if ('v' + installedVersion != targetTag) {
            confirmed = confirm('Update ceramic to $targetTag? (y/n)');
        }
        else {
            confirmed = confirm('Reinstall ceramic $targetTag? (y/n)');
        }

        if (confirmed) {
            // Delete any existing zip
            if (FileSystem.exists(ceramicZipPath)) {
                deleteRecursive(ceramicZipPath);
            }

            // Download
            downloadFile('https://github.com/ceramic-engine/ceramic/releases/download/$targetTag/ceramic-$platform.zip', ceramicZipPath);

            // Delete any existing ceramic installation
            if (FileSystem.exists(ceramicPath)) {
                deleteRecursive(ceramicPath);
            }

            // Extract files
            extractFile(ceramicZipPath, ceramicPath);

            var confirmLink = confirm('Make `ceramic` command available globally? (y/n)');
            if (confirmLink) {
                runCeramic(ceramicPath, ['link']);
            }
            runCeramic(ceramicPath, ['help']);
        }

    }

    static function resolveCeramicParentDir(cwd:String):String {

        var normalized = Path.normalize(cwd);
        var parts = normalized.split('/');
        var packageDir = 'ceramic/tools/package.json';

        while (!FileSystem.exists(Path.join([parts.join('/'), packageDir])) && parts.length > 1) {
            parts.pop();
        }

        if (FileSystem.exists(Path.join([parts.join('/'), packageDir]))) {
            return Path.normalize(parts.join('/'));
        }

        return normalized;

    }

    static function runCeramic(cwd:String, args:Array<String>):Void {

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
            Sys.command('./ceramic', args);
        }
        Sys.setCwd(prevCwd);

    }

    static function requestUrl(url:String):String {

        var result:String = null;

        var request = new HttpRequest({
            async: false,
            url: url,
            callback: function(response:HttpResponse):Void {
                if (response.isOK) {
                    result = response.content;
                }
                else {
                    throw 'Http error: ' + response.status + ' / ' + response.error;
                }
            }
        });

        request.send();

        return result;

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

    static function extractFile(sourceZIP:String, targetPath:String, ignoreRootFolder:String = ""):Void {

        var file = File.read(sourceZIP, true);
        var entries = Reader.readZip(file);
        file.close();

        var isWindows = Sys.systemName() == 'Windows';

        var numFiles = 0;

        for (entry in entries) {
            var fileName = entry.fileName;

            if (fileName.charAt(0) != "/" && fileName.charAt(0) != "\\" && fileName.split("..").length <= 1) {
                var dirs = ~/[\/\\]/g.split(fileName);

                if ((ignoreRootFolder != "" && dirs.length > 1) || ignoreRootFolder == "") {
                    if (ignoreRootFolder != "") {
                        dirs.shift();
                    }

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

                    print("Extract " + path);

                    var data = Reader.unzip(entry);
                    var f = File.write(targetPath + "/" + path, true);

                    if (!isWindows) {
                        Sys.command('chmod', ['755', targetPath + "/" + path]);
                    }

                    f.write(data);
                    f.close();
                }
            }
        }

        print("Done");
        
    }

    static function deleteRecursive(toDelete:String):Void {
        
        if (!FileSystem.exists(toDelete)) return;

        if (FileSystem.isDirectory(toDelete)) {

            for (name in FileSystem.readDirectory(toDelete)) {

                var path = Path.join([toDelete, name]);
                if (FileSystem.isDirectory(path)) {
                    deleteRecursive(path);
                } else {
                    FileSystem.deleteFile(path);
                }
            }

            FileSystem.deleteDirectory(toDelete);

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
