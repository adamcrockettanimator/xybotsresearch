#target photoshop

(function () {
    var reference = new ActionReference();
    reference.putProperty(charIDToTypeID("Prpr"), stringIDToTypeID("frameCount"));
    reference.putClass(stringIDToTypeID("animationClass"));
    var descriptor = executeActionGet(reference);
    return "document=" + app.activeDocument.name + "; layers=" + app.activeDocument.layers.length + "; timeline_frames=" + descriptor.getInteger(stringIDToTypeID("frameCount")) + "; width=" + app.activeDocument.width.as("px") + "; height=" + app.activeDocument.height.as("px");
}());
