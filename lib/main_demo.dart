import 'package:flutter/material.dart';
import 'package:flutter_screenutil/flutter_screenutil.dart';

void main() {
  runApp(const MyApp());
}

class MyApp extends StatelessWidget {
  const MyApp({super.key});

  @override
  Widget build(BuildContext context) {
    return ScreenUtilInit(
      designSize: const Size(390, 844),
      minTextAdapt: true,
      splitScreenMode: true,
      builder: (context, child) {
        return MaterialApp(
          title: 'ANTE Facial Recognition',
          theme: ThemeData(
            colorScheme: ColorScheme.fromSeed(seedColor: Colors.blue),
            useMaterial3: true,
          ),
          home: const DemoScreen(),
          debugShowCheckedModeBanner: false,
        );
      },
    );
  }
}

class DemoScreen extends StatelessWidget {
  const DemoScreen({super.key});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        backgroundColor: Theme.of(context).colorScheme.inversePrimary,
        title: const Text('ANTE Facial Recognition'),
      ),
      body: Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: <Widget>[
            Icon(
              Icons.face,
              size: 100.sp,
              color: Theme.of(context).colorScheme.primary,
            ),
            SizedBox(height: 20.h),
            Text(
              'Face Recognition Demo',
              style: TextStyle(fontSize: 24.sp, fontWeight: FontWeight.bold),
            ),
            SizedBox(height: 10.h),
            Text(
              'Project is running successfully!',
              style: TextStyle(fontSize: 16.sp),
            ),
            SizedBox(height: 30.h),
            ElevatedButton.icon(
              onPressed: () {
                ScaffoldMessenger.of(context).showSnackBar(
                  const SnackBar(content: Text('Camera would open here')),
                );
              },
              icon: const Icon(Icons.camera_alt),
              label: const Text('Open Camera'),
              style: ElevatedButton.styleFrom(
                padding: EdgeInsets.symmetric(horizontal: 30.w, vertical: 15.h),
              ),
            ),
            SizedBox(height: 20.h),
            Card(
              margin: EdgeInsets.all(20.w),
              child: Padding(
                padding: EdgeInsets.all(20.w),
                child: Column(
                  children: [
                    Text('Project Status', style: TextStyle(fontSize: 18.sp, fontWeight: FontWeight.bold)),
                    SizedBox(height: 10.h),
                    Text('✓ Flutter SDK: Installed', style: TextStyle(fontSize: 14.sp)),
                    Text('✓ Android SDK: Configured', style: TextStyle(fontSize: 14.sp)),
                    Text('✓ Emulator: Running', style: TextStyle(fontSize: 14.sp)),
                    Text('✓ Dependencies: Loaded', style: TextStyle(fontSize: 14.sp)),
                  ],
                ),
              ),
            ),
            SizedBox(height: 20.h),
            Text(
              'Completion: 38.2%',
              style: TextStyle(fontSize: 16.sp, color: Colors.orange),
            ),
          ],
        ),
      ),
    );
  }
}