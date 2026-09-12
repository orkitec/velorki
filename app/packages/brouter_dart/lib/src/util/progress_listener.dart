// Port of btools.util.ProgressListener (BRouter v1.7.10).

abstract class ProgressListener {
  void updateProgress(String task, int progress);

  bool isCanceled();
}
