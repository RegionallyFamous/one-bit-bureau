import QtQuick
import "IconResolver.js" as IconResolver

Image {
  id: root

  readonly property var packCrop: IconResolver.packCropForSource(String(root.source))
  readonly property real clipScaleX: root.sourceSize.width > 0 ? root.sourceSize.width / 256 : 1
  readonly property real clipScaleY: root.sourceSize.height > 0 ? root.sourceSize.height / 256 : 1

  sourceClipRect: root.packCrop
    ? Qt.rect(
        Math.round(root.packCrop.x * root.clipScaleX),
        Math.round(root.packCrop.y * root.clipScaleY),
        Math.round(root.packCrop.width * root.clipScaleX),
        Math.round(root.packCrop.height * root.clipScaleY)
      )
    : undefined
}
