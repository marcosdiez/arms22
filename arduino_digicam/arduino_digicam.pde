#include <stdio.h>
#include <FatFs.h>
#include <CameraC328R.h>
#include <NewSoftSerial.h>
#include <Bounce.h>
#include <EEPROM.h>
#include <Sleep.h>
#include <TinyGPS.h>
#include <Time.h>

// LED端子
const int ledRedPin   = 5;
const int ledGrnPin   = 6;

// スイッチ端子
const int wakeupPin   = 3;

// バッテリー電圧アナログ端子
const int vBatteryPin = 5;

// シャッタースイッチ
Bounce button(wakeupPin, 10);

void setup()
{
  Serial.begin(38400);

  pinMode(ledRedPin, OUTPUT);
  pinMode(ledGrnPin, OUTPUT);

  pinMode(wakeupPin, INPUT);
  digitalWrite(wakeupPin, HIGH);

  gps_init();

  sleep(11);
  button.update();

  sleep(11);
  button.update();

  // 日時初期化 2010/8/11 9:00:00
  setTime(9, 0, 0, 12, 8, 2010);

  // FATファイルシステム初期化
  if( FatFs.initialize() ){
    green(HIGH);
  }
  else{
init_error:
    attention(HIGH);
    while(1);
  }
}

unsigned long last_button_press = 0;
unsigned long last_heartbeat = 0;
unsigned long last_takepict  = 0;
unsigned long low_duration   = 0;
bool interval_mode           = false;
bool gps_logging             = false;
bool interval_mode_ind       = false;
bool gps_logging_ind         = false;
bool power_save              = true;

const uint8_t ledFadeStepTable[] = {
  0, 4, 8, 16, 32, 64, 128, 192, 224, 255, 255, 224, 192, 128, 64, 32, 16, 8, 4, 0,
};

void loop()
{
  // GPSデータ受信
  if( gps_logging ){
    if( gps_fetch() ){
      gps_encode();
      gps_writeData();
    }
  }

  if( power_save ){
    uint8_t fade_index = (millis() >> 6) & 0x7f;
    if(fade_index < sizeof(ledFadeStepTable)){
      analogWrite(ledGrnPin, ledFadeStepTable[fade_index]);
    }
    else{
      digitalWrite(ledGrnPin, LOW);
    }

    if( button.update() ){
      if( button.read() == HIGH ){
        last_button_press = millis();
        power_save = false;
        green(LOW);
      }
    }
  }
  else{

    // スリープしないように定期的にシンクコマンドを送る
    camera_sync();

    if( button.update() ){
      // ボタン Release
      if( button.read() == HIGH ){
        heartbeat();
        // 5.5秒以上の長押し
        if( low_duration > 5500 ){
          if( gps_logging ){
            // GPSログ OFF
            gps_logging = false;
            gps_powerOff();        
          }
          else{
            // GPSログ ON
            gps_logging = true;
            gps_powerOn();
          }
        }
        // 2.5秒以上の長押し
        else if( low_duration > 2500 ){
          // インターバル撮影 ON
          interval_mode = !interval_mode;
        }
        // 短押し
        else {
          // 通常撮影
          takePicture();
          button.update();

          // インターバル撮影を遅らせる
          last_takepict = millis();
        }
      }
      // ボタン Push
      else{
        gps_logging_ind = interval_mode_ind = false;
      }
    }

    // 長押し中
    if( button.read() == LOW ){
      // 長押しの時間を保存
      low_duration = button.duration();

      // インターバル撮影を遅らせる
      last_takepict = millis();

      // ハートビートを遅らせる
      last_heartbeat = millis();

      // 
      last_button_press = millis();

      // タイミングインジケート
      if( low_duration > 5500 && !gps_logging_ind){
        heartbeat();
        gps_logging_ind = true;
      }
      else if( low_duration > 2500 && !interval_mode_ind ){
        heartbeat();
        interval_mode_ind = true;
      }
    }

    // インターバル撮影モードなら最後の撮影から3秒経過していたら撮影する
    if( interval_mode ){
      if( millis() - last_takepict > 3000 ){
        takePicture();
        last_takepict = millis();
      }
    }
    else{
      // ハートビート
      if(millis() - last_heartbeat > 3000){
        heartbeat();
        last_heartbeat = millis();
      }

      // 最後の操作から60秒経過していたらパワーセーブモードに入る
      if( millis() - last_button_press > 60000 ){
        power_save = true;
      }
    }
  }
  sleep(1);
}

void takePicture(void)
{
  green(HIGH);
  attention(LOW);

  // GPSとの通信停止
  if( gps_logging ){
    gps_suspend(true);
  }

  // JPEG撮影
  bool success = getJPEGPicture();

  // GPSとの通信再開
  if( gps_logging ){
    gps_suspend(false);
  }

  green(LOW);
  if( !success ){
    attention(HIGH);
    sleep(5000);
  }
  attention(LOW);
}

void green(uint8_t on_off){
  if(on_off){
    analogWrite(ledGrnPin, 128);
  }
  else{
    digitalWrite(ledGrnPin, LOW);
  }
}

void attention(uint8_t on_off){
  if(on_off){
    analogWrite(ledRedPin, 128);
  }
  else{
    digitalWrite(ledRedPin, LOW);
  }
}

void heartbeat(void){
  green(HIGH);
  sleep(40);
  green(LOW);
  sleep(20);
}

#if FAT_DATETIME_SUPPORT
void get_datetime(uint16_t* y, uint8_t* m, uint8_t* d, uint8_t* h, uint8_t* n, uint8_t* s)
{
  time_t t = now();
  *y = year(t);
  *m = month();
  *d = day();
  *h = hour();
  *n = minute();
  *s = second();
}
#endif






