#target photoshop

(function () {
    app.displayDialogs = DialogModes.NO;

    var inputDir = new Folder("D:/Godot/xybotsResearch/mame-src/snap/xybots_capture/auto/stitched");
    var outputFile = new File("D:/Godot/xybotsResearch/mame-src/snap/xybots_capture/auto/xybots_stitched_layers_photoshop.psd");

    if (!inputDir.exists) {
        throw new Error("Input folder does not exist: " + inputDir.fsName);
    }

    var files = inputDir.getFiles(function (file) {
        return file instanceof File && /\.png$/i.test(file.name);
    });

    files.sort(function (a, b) {
        var an = decodeURI(a.name).toLowerCase();
        var bn = decodeURI(b.name).toLowerCase();
        if (an < bn) return -1;
        if (an > bn) return 1;
        return 0;
    });

    if (!files.length) {
        throw new Error("No PNG files found in: " + inputDir.fsName);
    }

    var doc = app.documents.add(
        512,
        512,
        72,
        "xybots_stitched_layers",
        NewDocumentMode.RGB,
        DocumentFill.TRANSPARENT,
        1,
        BitsPerChannelType.EIGHT
    );

    for (var i = 0; i < files.length; i++) {
        var src = app.open(files[i]);
        var layerName = decodeURI(files[i].name);

        src.activeLayer.name = layerName;
        src.activeLayer.duplicate(doc, ElementPlacement.PLACEATEND);
        src.close(SaveOptions.DONOTSAVECHANGES);

        app.activeDocument = doc;
        doc.activeLayer.name = layerName;

        var b = doc.activeLayer.bounds;
        var left = b[0].as("px");
        var top = b[1].as("px");
        doc.activeLayer.translate(-left, -top);

        if ((i + 1) % 100 === 0) {
            $.writeln("Imported " + (i + 1) + " / " + files.length);
        }
    }

    var saveOptions = new PhotoshopSaveOptions();
    saveOptions.layers = true;
    saveOptions.embedColorProfile = true;
    doc.saveAs(outputFile, saveOptions, true, Extension.LOWERCASE);

    alert("Wrote layered PSD:\n" + outputFile.fsName + "\n\nLayers: " + files.length);
})();
