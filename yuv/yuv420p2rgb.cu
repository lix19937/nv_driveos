/**************************************************************
 * @Copyright: 2021-2022 Copyright
 * @Author: lix
 * @Date: 2022-01-10 13:35:47
 * @Last Modified by: lix
 * @Last Modified time: 2022-01-14 14:32:53
 **************************************************************/

//  modules/imgproc/src/color_yuv.simd.hpp
//  modules/imgproc/src/color.cpp

#include <stdint.h>
#include <algorithm>
#include "opencv2/opencv.hpp"

static const int ITUR_BT_601_CY = 1220542;
static const int ITUR_BT_601_CUB = 2116026;
static const int ITUR_BT_601_CUG = -409993;
static const int ITUR_BT_601_CVG = -852492;
static const int ITUR_BT_601_CVR = 1673527;
static const int ITUR_BT_601_SHIFT = 20;

// YUV420p2RGB8Invoker

// R = 1.164(Y - 16) + 1.596(V - 128)
// G = 1.164(Y - 16) - 0.813(V - 128) - 0.391(U - 128)
// B = 1.164(Y - 16)                  + 2.018(U - 128)
//                   ===>
// R = (1220542(Y - 16) + 1673527(V - 128)                  + (1 << 19)) >> 20
// G = (1220542(Y - 16) - 852492(V - 128) - 409993(U - 128) + (1 << 19)) >> 20
// B = (1220542(Y - 16)                  + 2116026(U - 128) + (1 << 19)) >> 20
namespace {

inline void uvToRGBuv(
    const uint8_t u,
    const uint8_t v,
    int& ruv,
    int& guv, // NOLINT
    int& buv) { // NOLINT
  int uu, vv;
  uu = static_cast<int>(u) - 128;
  vv = static_cast<int>(v) - 128;
  ruv = (1 << (ITUR_BT_601_SHIFT - 1)) + ITUR_BT_601_CVR * vv;
  guv = (1 << (ITUR_BT_601_SHIFT - 1)) + ITUR_BT_601_CVG * vv + ITUR_BT_601_CUG * uu;
  buv = (1 << (ITUR_BT_601_SHIFT - 1)) + ITUR_BT_601_CUB * uu;
}

inline void yRGBuvToRGBA(
    const uint8_t vy,
    const int ruv,
    const int guv,
    const int buv,
    uint8_t& r,
    uint8_t& g, // NOLINT
    uint8_t& b, // NOLINT
    uint8_t& a) { // NOLINT
  int yy = static_cast<int>(vy);
  int y = std::max(0, yy - 16) * ITUR_BT_601_CY;

  auto saturate_cast = [](const int& v) { return (uint8_t)((unsigned)v <= UCHAR_MAX ? v : v > 0 ? UCHAR_MAX : 0); };

  r = saturate_cast((y + ruv) >> ITUR_BT_601_SHIFT);
  g = saturate_cast((y + guv) >> ITUR_BT_601_SHIFT);
  b = saturate_cast((y + buv) >> ITUR_BT_601_SHIFT);
  a = uint8_t(0xff);
}

template <int bIdx, int dcn, bool is420>
inline void yuv42xxp2rgb8(
    const uint8_t u,
    const uint8_t v,
    const uint8_t vy01,
    const uint8_t vy11,
    const uint8_t vy02,
    const uint8_t vy12,
    uint8_t* row1,
    uint8_t* row2) {
  int ruv, guv, buv;
  uvToRGBuv(u, v, ruv, guv, buv);

  uint8_t r00, g00, b00, a00;
  uint8_t r01, g01, b01, a01;

  yRGBuvToRGBA(vy01, ruv, guv, buv, r00, g00, b00, a00);
  yRGBuvToRGBA(vy11, ruv, guv, buv, r01, g01, b01, a01);

  row1[2 - bIdx] = r00;
  row1[1] = g00;
  row1[bIdx] = b00;
  if (dcn == 4) {
    row1[3] = a00;
  }

  row1[dcn + 2 - bIdx] = r01;
  row1[dcn + 1] = g01;
  row1[dcn + 0 + bIdx] = b01;
  if (dcn == 4) {
    row1[7] = a01;
  }

  if (is420) {
    uint8_t r10, g10, b10, a10;
    uint8_t r11, g11, b11, a11;

    yRGBuvToRGBA(vy02, ruv, guv, buv, r10, g10, b10, a10);
    yRGBuvToRGBA(vy12, ruv, guv, buv, r11, g11, b11, a11);

    row2[2 - bIdx] = r10;
    row2[1] = g10;
    row2[bIdx] = b10;
    if (dcn == 4) {
      row2[3] = a10;
    }

    row2[dcn + 2 - bIdx] = r11;
    row2[dcn + 1] = g11;
    row2[dcn + 0 + bIdx] = b11;
    if (dcn == 4) {
      row2[7] = a11;
    }
  }
}
} // namespace

template <int bIdx, int dcn, bool is420>
void yuv420p2rgb(
    uint8_t* dst_data, /* rgb */
    size_t stride, /* width */
    size_t dst_step, /* width*c */
    int width,
    int height,
    const uint8_t* _y,
    const uint8_t* _u,
    const uint8_t* _v) {
  int ustepIdx = 0, vstepIdx = 0;
  ////////// NOTE  dcn = 3;  // rgb/bgr is 3, rgba/bgra is 4
  //////////       bIdx = 2; // rgb is 2, bgr is 0   `B` location index

  const int rangeBegin{0};
  const int rangeEnd{height};
  int uvsteps[2]{width / 2, static_cast<int>(stride) - width / 2};
  int usIdx = ustepIdx, vsIdx = vstepIdx;

  auto y1 = _y;
  auto u1 = _u;
  auto v1 = _v;

  for (int j = rangeBegin; j < rangeEnd;
       j += 2, y1 += stride * 2, u1 += uvsteps[(usIdx++) & 1], v1 += uvsteps[(vsIdx++) & 1]) {
    auto row1 = dst_data + dst_step * j;
    auto row2 = dst_data + dst_step * (j + 1);
    const auto y2 = y1 + stride;

    for (int i = 0; i < width / 2; i += 1, row1 += dcn * 2, row2 += dcn * 2) {
      auto u = u1[i];
      auto v = v1[i];

      auto vy01 = y1[2 * i];
      auto vy11 = y1[2 * i + 1];
      auto vy02 = y2[2 * i];
      auto vy12 = y2[2 * i + 1];

      yuv42xxp2rgb8<bIdx, dcn, is420>(u, v, vy01, vy11, vy02, vy12, row1, row2);
    }
  }
}

int main() {
  auto img_bgr = cv::imread("debug.png");
  // cv::imshow("original", img_bgr);
  // cv::waitKey(0);

  int w = img_bgr.cols;
  int h = img_bgr.rows;
  int c = img_bgr.channels();

  ////// Convert from BGR to YUV, Just to get YUV420 data
  cv::Mat img_yuv420(h * 1.5, w, CV_8UC1, cv::Scalar::all(0));
  cv::cvtColor(img_bgr, img_yuv420, cv::COLOR_BGR2YUV_I420);
  cv::imwrite("img_yuv420.png", img_yuv420);

  ////// YUV420 TO BGR
  cv::Mat img_bgr_gt;
  cv::cvtColor(img_yuv420, img_bgr_gt, cv::COLOR_YUV2BGR_I420);
  cv::imwrite("img_bgr_gt.png", img_bgr_gt);

  ////// Byself
  cv::Mat img_bgr_ref(h, w, CV_8UC3, cv::Scalar::all(0));

  auto y = img_yuv420.data;
  auto u = y + h * w;
  auto v = u + h * w / 4;

  yuv420p2rgb<0, 3, true>(img_bgr_ref.data, w, 3 * w, w, h, y, u, v);

  cv::imwrite("img_bgr_ref.png", img_bgr_ref);
  return 0;
}

/*
export LD_LIBRARY_PATH=$LD_LIBRARY_PATH:/mnt/d/workspace/opencv-4.9.0/build/install_local/lib
g++ -std=c++14 -O2 ./yuv420p2rgb.cpp  -lopencv_core -lopencv_imgproc -lopencv_highgui -lopencv_imgcodecs \
-I/mnt/d/workspace/opencv-4.9.0/build/install_local/include/opencv4 \
-L/mnt/d/workspace/opencv-4.9.0/build/install_local/lib


*/
