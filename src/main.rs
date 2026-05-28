#![no_std]
#![no_main]

use core::sync::atomic::{AtomicU16, Ordering};

use embassy_executor::Spawner;
use embassy_rp::{
    adc::{self, Adc, Channel},
    bind_interrupts,
    dma,
    gpio::Pull,
    peripherals,
    pio::{self, Pio},
    pio_programs::ws2812::{Grb, PioWs2812, PioWs2812Program},
    pwm::{Config as PwmConfig, Pwm, SetDutyCycle},
};
use embassy_time::{Duration, Timer};
use panic_halt as _;
use smart_leds::RGB8;

bind_interrupts!(struct Irqs {
    ADC_IRQ_FIFO => adc::InterruptHandler;
    PIO0_IRQ_0 => pio::InterruptHandler<peripherals::PIO0>;
    DMA_IRQ_0 => dma::InterruptHandler<peripherals::DMA_CH0>;
});

const ADC_MAX: u16 = 4095;
const BOARD_LED_BRIGHTNESS: u8 = 24;

static ADC_VALUE: AtomicU16 = AtomicU16::new(0);

#[embassy_executor::main]
async fn main(spawner: Spawner) {
    let p = embassy_rp::init(Default::default());

    let mut adc = Adc::new(p.ADC, Irqs, adc::Config::default());
    let mut pot = Channel::new_pin(p.PIN_26, Pull::None);

    let mut pwm_config = PwmConfig::default();
    pwm_config.phase_correct = true;
    pwm_config.top = ADC_MAX;
    pwm_config.compare_b = 0;
    let mut led_pwm = Pwm::new_output_b(p.PWM_SLICE7, p.PIN_15, pwm_config);

    let mut pio = Pio::new(p.PIO0, Irqs);
    let ws2812_program = PioWs2812Program::new(&mut pio.common);
    let board_led = PioWs2812::<_, 0, 1, Grb>::new(
        &mut pio.common,
        pio.sm0,
        p.DMA_CH0,
        Irqs,
        p.PIN_16,
        &ws2812_program,
    );

    spawner.spawn(board_led_task(board_led).unwrap());

    loop {
        let value = adc.read(&mut pot).await.unwrap_or(0).min(ADC_MAX);
        ADC_VALUE.store(value, Ordering::Relaxed);
        led_pwm.set_duty_cycle(value).unwrap();
        Timer::after(Duration::from_millis(10)).await;
    }
}

#[embassy_executor::task]
async fn board_led_task(mut led: PioWs2812<'static, peripherals::PIO0, 0, 1, Grb>) {
    let mut is_on = false;

    loop {
        let value = ADC_VALUE.load(Ordering::Relaxed);
        is_on = !is_on;

        let color = if is_on {
            scale_color(board_led_color(value), BOARD_LED_BRIGHTNESS)
        } else {
            RGB8::default()
        };

        led.write(&[color]).await;
        Timer::after(Duration::from_millis(blink_half_period_ms(value))).await;
    }
}

fn blink_half_period_ms(adc_value: u16) -> u64 {
    match adc_value {
        0..=819 => 900,
        820..=1638 => 600,
        1639..=2457 => 350,
        2458..=3276 => 180,
        _ => 80,
    }
}

fn board_led_color(adc_value: u16) -> RGB8 {
    match adc_value {
        0..=819 => RGB8 { r: 0, g: 0, b: 255 },
        820..=1638 => RGB8 { r: 0, g: 255, b: 255 },
        1639..=2457 => RGB8 { r: 0, g: 255, b: 0 },
        2458..=3276 => RGB8 { r: 255, g: 180, b: 0 },
        _ => RGB8 { r: 255, g: 0, b: 0 },
    }
}

fn scale_color(color: RGB8, brightness: u8) -> RGB8 {
    RGB8 {
        r: scale_u8(color.r, brightness),
        g: scale_u8(color.g, brightness),
        b: scale_u8(color.b, brightness),
    }
}

fn scale_u8(value: u8, brightness: u8) -> u8 {
    ((value as u16 * brightness as u16) / 255) as u8
}
