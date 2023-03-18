import 'dart:async';
import 'dart:io';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:camera/camera.dart';
import 'package:google_ml_kit/google_ml_kit.dart';
import 'package:path_provider/path_provider.dart';
import 'package:path/path.dart';
import 'package:flutter_spinkit/flutter_spinkit.dart';
import 'package:toast/toast.dart';
import 'package:touchable/touchable.dart';
import 'package:gallery_saver/gallery_saver.dart';

late List<CameraDescription> cameras;

void main() async {
  WidgetsFlutterBinding.ensureInitialized();
  cameras = await availableCameras();
  runApp(MyApp());
}

class MyApp extends StatelessWidget {
  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'Object Detection',
      theme: ThemeData(
        primarySwatch: Colors.blue,
      ),
      home: CanineCam(),
    );
  }
}

class CanineCam extends StatefulWidget {
  CanineCam({Key? key}) : super(key: key);

  @override
  _CanineCamState createState() {
    return _CanineCamState();
  }
}

class _CanineCamState extends State<CanineCam> {
  dynamic controller;
  dynamic objectDetector;
  dynamic _detectedObjects;
  double? maxZoomLevel;
  CameraImage? img;
  bool isPaused = false;
  bool isBusy = false;
  bool isStreamStopped = true;
  List<Widget> stackChildren = [];

// Function to get the path of the fine-tuned model
  Future<String> _getModel(String assetPath) async {
    if (Platform.isAndroid) {
      return 'flutter_assets/$assetPath';
    }
    final path = '${(await getApplicationSupportDirectory()).path}/$assetPath';
    await Directory(dirname(path)).create(recursive: true);
    final file = File(path);
    if (!await file.exists()) {
      final byteData = await rootBundle.load(assetPath);
      await file.writeAsBytes(byteData.buffer
          .asUint8List(byteData.offsetInBytes, byteData.lengthInBytes));
    }
    return file.path;
  }

  @override
  void initState() {
    super.initState();
    initModel();
    initCamera();
  }

  initModel() async {
    final modelPath = await _getModel('assets/ml/model.tflite');
    final options = LocalObjectDetectorOptions(
        modelPath: modelPath,
        classifyObjects: true,
        multipleObjects: true,
        mode: DetectionMode.stream,
        confidenceThreshold: 0.7);
    objectDetector = ObjectDetector(options: options);
  }

// This function initializes the camera and starts image stream
// We declare controller as dynamic since the controller might return null (when not initialized, async!)
  initCamera() async {
    controller = CameraController(cameras[0], ResolutionPreset.high);
    await controller.initialize().then((_) async {
      maxZoomLevel = await controller.getMaxZoomLevel();
      await startStream();
      if (!mounted) {
        return;
      }
    }).catchError((Object e) {
      if (e is CameraException) {
        switch (e.code) {
          case 'CameraAccessDenied':
            print('Camera access denied!');
            break;
          default:
            print('Camera initalization error!');
            break;
        }
      }
    });
  }

  startStream() async {
    if (isStreamStopped == true) {
      await controller.startImageStream((image) async {
        if (!isBusy) {
          isBusy = true;
          isStreamStopped = false;
          img = image;
          await performDetectionOnFrame();
        }
      });
    }
  }

  stopStream() async {
    await controller.stopImageStream();
  }

  performDetectionOnFrame() async {
    InputImage frameImg = getInputImage();
    List<DetectedObject> objects = await objectDetector.processImage(frameImg);
    double zoomLevel = await controller.getMaxZoomLevel();
    setState(() {
      _detectedObjects = objects;
    });
    isBusy = false;
  }

// This function will convert the cameraImage to an InputImage so we can use it for processing
  InputImage getInputImage() {
    final WriteBuffer allBytes = WriteBuffer();
    for (final Plane plane in img!.planes) {
      allBytes.putUint8List(plane.bytes);
    }
    final bytes = allBytes.done().buffer.asUint8List();
    final Size imageSize = Size(img!.width.toDouble(), img!.height.toDouble());
    final camera = cameras[0];

    final planeData = img!.planes.map(
      (Plane plane) {
        return InputImagePlaneMetadata(
          bytesPerRow: plane.bytesPerRow,
          height: plane.height,
          width: plane.width,
        );
      },
    ).toList();

    final inputImageData = InputImageData(
      size: imageSize,
      imageRotation:
          InputImageRotationValue.fromRawValue(camera.sensorOrientation)!,
      inputImageFormat: InputImageFormatValue.fromRawValue(img!.format.raw)!,
      planeData: planeData,
    );

    final inputImage =
        InputImage.fromBytes(bytes: bytes, inputImageData: inputImageData);

    return inputImage;
  }

  //Show rectangles around detected objects
  Widget drawRectangleOverObjects() {
    if (_detectedObjects == null ||
        controller == null ||
        !controller.value.isInitialized) {
      return Text('');
    }

    final Size imageSize = Size(
      controller.value.previewSize!.height,
      controller.value.previewSize!.width,
    );
    return CanvasTouchDetector(
      gesturesToOverride: [GestureType.onTapDown],
      builder: (context) => CustomPaint(
        painter: ObjectPainter(
            context, controller, maxZoomLevel!, imageSize, _detectedObjects),
      ),
    );
  }

  @override
  void dispose() {
    controller?.dispose();
    objectDetector?.close();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    Size size = MediaQuery.of(context).size;
    ToastContext().init(context);
    if (controller != null) {
      // stackChildren.add(Positioned(top: 0.0, left: 0.0, child: Text(text)));
      stackChildren.add(
        Positioned(
          top: 0.0,
          left: 0.0,
          width: size.width,
          height: size.height,
          child: Container(
            child: (controller.value.isInitialized)
                ? AspectRatio(
                    aspectRatio: controller.value.aspectRatio,
                    child: CameraPreview(controller),
                  )
                : Container(),
          ),
        ),
      );
      if (isPaused == false) {
        stackChildren.add(
          Positioned(
              top: 0.0,
              left: 0.0,
              width: size.width,
              height: size.height,
              child: drawRectangleOverObjects()),
        );
      }
    }
    return Scaffold(
        floatingActionButton:
            Row(mainAxisAlignment: MainAxisAlignment.spaceAround, children: [
          FloatingActionButton(
            onPressed: () async {
              controller.setZoomLevel(await controller.getMinZoomLevel());
              Toast.show("Zoom reset!",
                  duration: Toast.lengthShort, gravity: Toast.bottom);
            },
            child: Icon(Icons.zoom_out),
          ),
          FloatingActionButton(
            onPressed: () async {
              // Stopping stream because can't take picture without stopping the stream!
              if (isStreamStopped == false) {
                await stopStream();
                setState(() {
                  isStreamStopped = true;
                });
                await controller.lockCaptureOrientation();
                final image = await controller.takePicture();
                if (image != null) {
                  final fileName = basename(image.path);
                  final filePath = await getApplicationDocumentsDirectory();
                  await image.saveTo('${filePath.path}/$fileName');
                  GallerySaver.saveImage(image.path).then((success) {
                    if (success = true) {
                      Toast.show("Picture captured and saved!",
                          duration: Toast.lengthShort, gravity: Toast.bottom);
                    } else {
                      Toast.show("Picture couldn't be captured!",
                          duration: Toast.lengthShort, gravity: Toast.bottom);
                    }
                  });
                  await startStream();
                }
              } else {
                Toast.show("Camera is loading!",
                    duration: Toast.lengthShort, gravity: Toast.bottom);
              }
            },
            child: Icon(Icons.camera),
          ),
          FloatingActionButton(
            onPressed: () async {
              if (isPaused == true) {
                setState(() {
                  isPaused = false;
                });
                Toast.show("Camera preview resumed!",
                    duration: Toast.lengthShort, gravity: Toast.bottom);
                await controller.resumePreview();
              } else {
                stackChildren.removeRange(0, stackChildren.length);
                setState(() {
                  isPaused = true;
                  stackChildren = stackChildren;
                });
                Toast.show("Camera preview paused!",
                    duration: Toast.lengthShort, gravity: Toast.bottom);
                await controller.pausePreview();
              }
            },
            child: (isPaused == false)
                ? Icon(Icons.pause)
                : Icon(Icons.play_arrow),
          )
        ]),
        appBar: AppBar(
          title: const Text('CanineCam'),
          centerTitle: true,
        ),
        body: (controller == null)
            ? Container(
                child: Center(
                child: Column(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      Text('Loading...'),
                      SpinKitRotatingCircle(
                        color: Colors.grey,
                        size: 30.0,
                      )
                    ]),
              ))
            : Container(
                child: Stack(
                children: stackChildren,
              )));
  }
}

class ObjectPainter extends CustomPainter {
  ObjectPainter(this.context, this.controller, this.maxZoomLevel, this.imgSize,
      this.objects);

  final BuildContext context;
  final Size imgSize;
  final List<DetectedObject> objects;
  final double maxZoomLevel;
  CameraController controller;

  @override
  void paint(Canvas canvas, Size size) {
    // Using TouchyCanvas to enable interactivity
    TouchyCanvas touchyCanvas = TouchyCanvas(context, canvas);
    // Calculating the scale factor to resize the rectangle (newSize/originalSize)
    final double scaleX = size.width / imgSize.width;
    final double scaleY = size.height / imgSize.height;

    final Paint paint = Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = 10.0
      ..color = Color.fromARGB(255, 255, 0, 0);

    for (DetectedObject detectedObject in objects) {
      touchyCanvas.drawRect(
        Rect.fromLTRB(
          detectedObject.boundingBox.left * scaleX,
          detectedObject.boundingBox.top * scaleY,
          detectedObject.boundingBox.right * scaleX,
          detectedObject.boundingBox.bottom * scaleY,
        ),
        paint,
        onTapDown: (tapDetail) {
          final double zoomScaleX =
              size.width / detectedObject.boundingBox.width;
          final double zoomScaleY =
              size.height / detectedObject.boundingBox.height;
          // controller.setFocusPoint(detectedObject.boundingBox.center);
          double zoomLevel = maxZoomLevel;
          if (zoomScaleX > zoomScaleY) {
            if (zoomScaleX < maxZoomLevel) {
              zoomLevel = zoomScaleX;
            }
          } else {
            if (zoomScaleY < maxZoomLevel) {
              zoomLevel = zoomScaleY;
            }
          }
          controller.setZoomLevel(zoomLevel);
          Toast.show("Zooming!",
              duration: Toast.lengthShort, gravity: Toast.bottom);
        },
      );
    }
  }

  @override
  bool shouldRepaint(ObjectPainter oldDelegate) {
    // Repaint if object is moving or new objects detected
    return oldDelegate.imgSize != imgSize || oldDelegate.objects != objects;
  }
}
