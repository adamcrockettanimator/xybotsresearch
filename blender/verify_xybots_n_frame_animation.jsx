#target photoshop

(function () {
    var reference = new ActionReference();
    reference.putProperty(charIDToTypeID("Prpr"), stringIDToTypeID("frameCount"));
    reference.putClass(stringIDToTypeID("animationClass"));
    var descriptor = executeActionGet(reference);
    var names = [];
    for (var i = 0; i < app.documents.length; i++) names.push(app.documents[i].name + "(" + app.documents[i].layers.length + ")");
    return "document=" + app.activeDocument.name + "; layers=" + app.activeDocument.layers.length + "; timeline_frames=" + descriptor.getInteger(stringIDToTypeID("frameCount")) + "; open=" + names.join(", ");
}());
