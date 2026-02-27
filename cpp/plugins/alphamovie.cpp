/**
 * @file alphamovie.cpp
 * @brief Minimal AlphaMovie stub plugin for KiriKiri2.
 *
 * Provides enough of the AlphaMovie interface so that games which
 * reference AlphaMovie.dll do not crash.  Actual video playback is
 * not implemented — calls are silently ignored.
 */

#include "ncbind.hpp"

#define NCB_MODULE_NAME TJS_W("AlphaMovie.dll")

class AlphaMovie {
public:
  AlphaMovie() {}
  virtual ~AlphaMovie() {}

  void open(tTJSVariant) {}
  void play() {}
  void stop() {}
  void pause() {}
  void close() {}
  void rewind() {}

  bool get_loop() const { return m_loop; }
  void set_loop(bool v) { m_loop = v; }

  bool get_visible() const { return m_visible; }
  void set_visible(bool v) { m_visible = v; }

  int get_frame() const { return 0; }
  void set_frame(int) {}

  double get_fps() const { return 30.0; }
  void set_fps(double) {}

  int get_position() const { return 0; }
  void set_position(int) {}

  int get_width() const { return 0; }
  int get_height() const { return 0; }

  bool get_opened() const { return false; }
  bool get_isPlaying() const { return false; }

  int get_totalTime() const { return 0; }
  int get_numberOfFrame() const { return 0; }

private:
  bool m_loop = false;
  bool m_visible = false;
};

NCB_REGISTER_CLASS(AlphaMovie) {
  Constructor();

  NCB_METHOD(open);
  NCB_METHOD(play);
  NCB_METHOD(stop);
  NCB_METHOD(pause);
  NCB_METHOD(close);
  NCB_METHOD(rewind);

  NCB_PROPERTY(loop, get_loop, set_loop);
  NCB_PROPERTY(visible, get_visible, set_visible);
  NCB_PROPERTY(frame, get_frame, set_frame);
  NCB_PROPERTY(fps, get_fps, set_fps);
  NCB_PROPERTY(position, get_position, set_position);
  NCB_PROPERTY_RO(width, get_width);
  NCB_PROPERTY_RO(height, get_height);
  NCB_PROPERTY_RO(opened, get_opened);
  NCB_PROPERTY_RO(isPlaying, get_isPlaying);
  NCB_PROPERTY_RO(totalTime, get_totalTime);
  NCB_PROPERTY_RO(numberOfFrame, get_numberOfFrame);
};
