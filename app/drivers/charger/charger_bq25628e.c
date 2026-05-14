#define DT_DRV_COMPAT ti_bq25628e

#include <errno.h>
#include <zephyr/device.h>
#include <zephyr/drivers/charger.h>
#include <zephyr/drivers/i2c.h>
#include <zephyr/sys/byteorder.h>

#include <zephyr/logging/log.h>
LOG_MODULE_REGISTER(ti_bq25628e, CONFIG_CHARGER_LOG_LEVEL);

#define BQ25628E_REG_CHARGE_CURRENT_LOW 0x02
#define BQ25628E_CHARGE_CURRENT_MASK GENMASK(10, 5)
#define BQ25628E_ICHG_MIN_UA 40000U
#define BQ25628E_ICHG_MAX_UA 2000000U
#define BQ25628E_ICHG_STEP_UA 40000U

#define BQ25628E_REG_CHARGE_VOLTAGE_LOW 0x04
#define BQ25628E_VREG_MASK GENMASK(11, 3)
#define BQ25628E_VREG_MIN_UV 3500000U
#define BQ25628E_VREG_MAX_UV 4800000U
#define BQ25628E_VREG_STEP_UV 10000U

#define BQ25628E_REG_INPUT_CURRENT_LOW 0x06
#define BQ25628E_IINDPM_MASK GENMASK(11, 4)
#define BQ25628E_IINDPM_MIN_UA 100000U
#define BQ25628E_IINDPM_MAX_UA 3200000U
#define BQ25628E_IINDPM_STEP_UA 20000U

#define BQ25628E_REG_INPUT_VOLTAGE_LOW 0x08
#define BQ25628E_VINDPM_MASK GENMASK(13, 5)
#define BQ25628E_VINDPM_MIN_UV 3800000U
#define BQ25628E_VINDPM_MAX_UV 16800000U
#define BQ25628E_VINDPM_STEP_UV 40000U

#define BQ25628E_REG_PRECHARGE_CONTROL_LOW 0x10
#define BQ25628E_IPRECHG_MASK GENMASK(7, 3)
#define BQ25628E_IPRECHG_MIN_UA 10000U
#define BQ25628E_IPRECHG_MAX_UA 310000U
#define BQ25628E_IPRECHG_STEP_UA 10000U

#define BQ25628E_REG_TERMINATION_CONTROL_LOW 0x12
#define BQ25628E_ITERM_MASK GENMASK(7, 2)
#define BQ25628E_ITERM_MIN_UA 5000U
#define BQ25628E_ITERM_MAX_UA 310000U
#define BQ25628E_ITERM_STEP_UA 5000U

#define BQ25628E_REG_CHARGE_CONTROL 0x14
#define BQ25628E_Q1_FULLON_MASK BIT(7)
#define BQ25628E_Q4_FULLON_MASK BIT(6)
#define BQ25628E_ITRICKLE_MASK BIT(5)
#define BQ25628E_TOPOFF_TMR_MASK GENMASK(4, 3)
#define BQ25628E_EN_TERM_MASK BIT(2)
#define BQ25628E_VINDPM_BAT_TRACK_MASK BIT(1)
#define BQ25628E_VRECHG_MASK BIT(0)
#define BQ25628E_ITRICKLE_10MA_UA 10000U
#define BQ25628E_ITRICKLE_40MA_UA 40000U
#define BQ25628E_VRECHG_100MV_UV 100000U
#define BQ25628E_VRECHG_200MV_UV 200000U

#define BQ25628E_REG_CHARGE_TIMER_CONTROL 0x15
#define BQ25628E_DIS_STAT_MASK BIT(7)
#define BQ25628E_TMR2X_EN_MASK BIT(3)
#define BQ25628E_EN_SAFETY_TMRS_MASK BIT(2)
#define BQ25628E_PRECHG_TMR_MASK BIT(1)
#define BQ25628E_CHG_TMR_MASK BIT(0)
#define BQ25628E_PRECHG_TMR_2P5H_SEC 9000U
#define BQ25628E_PRECHG_TMR_0P62H_SEC 2232U
#define BQ25628E_CHG_TMR_14P5H_SEC 52200U
#define BQ25628E_CHG_TMR_28H_SEC 100800U

#define BQ25628E_REG_CHARGER_CONTROL_0 0x16
#define BQ25628E_EN_AUTO_IBATDIS_MASK BIT(7)
#define BQ25628E_FORCE_IBATDIS_MASK BIT(6)
#define BQ25628E_EN_CHG_MASK BIT(5)
#define BQ25628E_EN_HIZ_MASK BIT(4)
#define BQ25628E_FORCE_PMID_DIS_MASK BIT(3)
#define BQ25628E_WD_RST_MASK BIT(2)
#define BQ25628E_WATCHDOG_MASK GENMASK(1, 0)
#define BQ25628E_WATCHDOG_DISABLED_SEC 0U
#define BQ25628E_WATCHDOG_50_SEC 50U
#define BQ25628E_WATCHDOG_100_SEC 100U
#define BQ25628E_WATCHDOG_200_SEC 200U

#define BQ25628E_REG_CHARGER_CONTROL_1 0x17
#define BQ25628E_REG_RST_MASK BIT(7)
#define BQ25628E_TREG_MASK BIT(6)
#define BQ25628E_SET_CONV_FREQ_MASK GENMASK(5, 4)
#define BQ25628E_SET_CONV_STRN_MASK GENMASK(3, 2)
#define BQ25628E_VBUS_OVP_MASK BIT(0)
#define BQ25628E_TREG_60C 60U
#define BQ25628E_TREG_120C 120U
#define BQ25628E_CONV_FREQ_1P5MHZ_HZ 1500000U
#define BQ25628E_CONV_FREQ_1P35MHZ_HZ 1350000U
#define BQ25628E_CONV_FREQ_1P65MHZ_HZ 1650000U
#define BQ25628E_VBUS_OVP_6P3V_UV 6300000U
#define BQ25628E_VBUS_OVP_18P5V_UV 18500000U

enum bq25628e_converter_drive_strength {
    BQ25628E_CONV_STRN_WEAK   = 0,
    BQ25628E_CONV_STRN_NORMAL = 1,
    BQ25628E_CONV_STRN_STRONG = 3,
};

#define BQ25628E_REG_CHARGER_CONTROL_2 0x18
#define BQ25628E_PFM_FWD_DIS_MASK BIT(4)
#define BQ25628E_BATFET_CTRL_WVBUS_MASK BIT(3)
#define BQ25628E_BATFET_DLY_MASK BIT(2)
#define BQ25628E_BATFET_CTRL_MASK GENMASK(1, 0)
#define BQ25628E_BATFET_DLY_25_MS 25U
#define BQ25628E_BATFET_DLY_12P5_SEC_MS 12500U

enum bq25628e_batfet_ctrl {
    BQ25628E_BATFET_CTRL_NORMAL             = 0,
    BQ25628E_BATFET_CTRL_SHUTDOWN           = 1,
    BQ25628E_BATFET_CTRL_SHIP               = 2,
    BQ25628E_BATFET_CTRL_SYSTEM_POWER_RESET = 3,
};

#define BQ25628E_REG_CHARGER_STATUS_0 0x1d
#define BQ25628E_ADC_DONE_STAT_MASK BIT(6)
#define BQ25628E_TREG_STAT_MASK BIT(5)
#define BQ25628E_VSYS_STAT_MASK BIT(4)
#define BQ25628E_IINDPM_STAT_MASK BIT(3)
#define BQ25628E_VINDPM_STAT_MASK BIT(2)
#define BQ25628E_SAFETY_TMR_STAT_MASK BIT(1)
#define BQ25628E_WD_STAT_MASK BIT(0)

#define BQ25628E_REG_CHARGER_STATUS_1 0x1e
#define BQ25628E_CHG_STAT_MASK GENMASK(4, 3)
#define BQ25628E_VBUS_STAT_MASK GENMASK(2, 0)

enum bq25628e_charge_status {
    BQ25628E_CHG_STAT_NOT_CHARGING      = 0,
    BQ25628E_CHG_STAT_TRICKLE_PRECHG_CC = 1,
    BQ25628E_CHG_STAT_TAPER_CV          = 2,
    BQ25628E_CHG_STAT_TOPOFF_TIMER      = 3,
};

enum bq25628e_vbus_status {
    BQ25628E_VBUS_STAT_NOT_POWERED     = 0,
    BQ25628E_VBUS_STAT_UNKNOWN_ADAPTER = 4,
};

#define BQ25628E_REG_CHARGER_FLAG_0 0x20
#define BQ25628E_ADC_DONE_FLAG_MASK BIT(6)
#define BQ25628E_TREG_FLAG_MASK BIT(5)
#define BQ25628E_VSYS_FLAG_MASK BIT(4)
#define BQ25628E_IINDPM_FLAG_MASK BIT(3)
#define BQ25628E_VINDPM_FLAG_MASK BIT(2)
#define BQ25628E_SAFETY_TMR_FLAG_MASK BIT(1)
#define BQ25628E_WD_FLAG_MASK BIT(0)

struct bq25628e_config {
    struct i2c_dt_spec i2c;

    uint32_t ichg_ua;
    uint32_t vreg_uv;
    uint32_t iindpm_ua;
    uint32_t vindpm_uv;
    uint32_t iprechg_ua;
    uint32_t iterm_ua;

    bool enable_watchdog;
    bool charge_termination_disabled;
};

static inline int bq25628e_write8(const struct device* dev, uint8_t reg, uint8_t value) {
    const struct bq25628e_config* const config = dev->config;

    return i2c_reg_write_byte_dt(&config->i2c, reg, value);
}

static inline int bq25628e_read8(const struct device* dev, uint8_t reg, uint8_t* value) {
    const struct bq25628e_config* const config = dev->config;
    int ret;

    ret = i2c_reg_read_byte_dt(&config->i2c, reg, value);
    if (ret < 0) {
        LOG_ERR("Unable to read register");
    }
    return ret;
}

static inline int bq25628e_write16(const struct device* dev, uint8_t reg, uint16_t value) {
    const struct bq25628e_config* const config = dev->config;
    uint8_t buf[3];

    buf[0] = reg;
    /* Avoid unaligned 16-bit stores on Cortex-M33. */
    buf[1] = (uint8_t)(value & 0xff);
    buf[2] = (uint8_t)(value >> 8);

    return i2c_write_dt(&config->i2c, buf, sizeof(buf));
}

static inline int bq25628e_read16(const struct device* dev, uint8_t reg, uint16_t* value) {
    const struct bq25628e_config* config = dev->config;
    uint8_t i2c_data[2];
    int ret;

    ret = i2c_burst_read_dt(&config->i2c, reg, i2c_data, sizeof(i2c_data));
    if (ret < 0) {
        LOG_ERR("Unable to read register");
    }
    /* Avoid unaligned 16-bit loads on Cortex-M33. */
    *value = (uint16_t)i2c_data[0] | ((uint16_t)i2c_data[1] << 8);

    return ret;
}

static int bq25628e_set_charge_current_limit(const struct device* dev, uint32_t current_ua) {
    uint16_t reg;
    uint16_t ichg;
    int ret;

    current_ua = CLAMP(current_ua, BQ25628E_ICHG_MIN_UA, BQ25628E_ICHG_MAX_UA);

    ichg = current_ua / BQ25628E_ICHG_STEP_UA;

    ret = bq25628e_read16(dev, BQ25628E_REG_CHARGE_CURRENT_LOW, &reg);
    if (ret < 0) {
        return ret;
    }

    reg &= ~BQ25628E_CHARGE_CURRENT_MASK;
    reg |= FIELD_PREP(BQ25628E_CHARGE_CURRENT_MASK, ichg);

    return bq25628e_write16(dev, BQ25628E_REG_CHARGE_CURRENT_LOW, reg);
}

static int bq25628e_get_charge_current_limit(const struct device* dev, uint32_t* current_ua) {
    uint16_t reg;
    uint16_t ichg;
    int ret;

    ret = bq25628e_read16(dev, BQ25628E_REG_CHARGE_CURRENT_LOW, &reg);
    if (ret < 0) {
        return ret;
    }

    ichg        = FIELD_GET(BQ25628E_CHARGE_CURRENT_MASK, reg);
    *current_ua = ichg * BQ25628E_ICHG_STEP_UA;

    return 0;
}

static int bq25628e_set_charge_voltage_limit(const struct device* dev, uint32_t voltage_uv) {
    uint16_t reg;
    uint16_t vreg;
    int ret;

    voltage_uv = CLAMP(voltage_uv, BQ25628E_VREG_MIN_UV, BQ25628E_VREG_MAX_UV);

    vreg = (voltage_uv - BQ25628E_VREG_MIN_UV) / BQ25628E_VREG_STEP_UV;

    ret = bq25628e_read16(dev, BQ25628E_REG_CHARGE_VOLTAGE_LOW, &reg);
    if (ret < 0) {
        return ret;
    }

    reg &= ~BQ25628E_VREG_MASK;
    reg |= FIELD_PREP(BQ25628E_VREG_MASK, vreg);

    return bq25628e_write16(dev, BQ25628E_REG_CHARGE_VOLTAGE_LOW, reg);
}

static int bq25628e_get_charge_voltage_limit(const struct device* dev, uint32_t* voltage_uv) {
    uint16_t reg;
    uint16_t vreg;
    int ret;

    ret = bq25628e_read16(dev, BQ25628E_REG_CHARGE_VOLTAGE_LOW, &reg);
    if (ret < 0) {
        return ret;
    }

    vreg        = FIELD_GET(BQ25628E_VREG_MASK, reg);
    *voltage_uv = BQ25628E_VREG_MIN_UV + (vreg * BQ25628E_VREG_STEP_UV);

    return 0;
}

static int bq25628e_set_input_current_limit(const struct device* dev, uint32_t current_ua) {
    uint16_t reg;
    uint16_t iindpm;
    int ret;

    current_ua = CLAMP(current_ua, BQ25628E_IINDPM_MIN_UA, BQ25628E_IINDPM_MAX_UA);

    iindpm = current_ua / BQ25628E_IINDPM_STEP_UA;

    ret = bq25628e_read16(dev, BQ25628E_REG_INPUT_CURRENT_LOW, &reg);
    if (ret < 0) {
        return ret;
    }

    reg &= ~BQ25628E_IINDPM_MASK;
    reg |= FIELD_PREP(BQ25628E_IINDPM_MASK, iindpm);

    return bq25628e_write16(dev, BQ25628E_REG_INPUT_CURRENT_LOW, reg);
}

static int bq25628e_get_input_current_limit(const struct device* dev, uint32_t* current_ua) {
    uint16_t reg;
    uint16_t iindpm;
    int ret;

    ret = bq25628e_read16(dev, BQ25628E_REG_INPUT_CURRENT_LOW, &reg);
    if (ret < 0) {
        return ret;
    }

    iindpm      = FIELD_GET(BQ25628E_IINDPM_MASK, reg);
    *current_ua = iindpm * BQ25628E_IINDPM_STEP_UA;

    return 0;
}

static int bq25628e_set_input_voltage_limit(const struct device* dev, uint32_t voltage_uv) {
    uint16_t reg;
    uint16_t vindpm;
    int ret;

    voltage_uv = CLAMP(voltage_uv, BQ25628E_VINDPM_MIN_UV, BQ25628E_VINDPM_MAX_UV);

    vindpm = voltage_uv / BQ25628E_VINDPM_STEP_UV;

    ret = bq25628e_read16(dev, BQ25628E_REG_INPUT_VOLTAGE_LOW, &reg);
    if (ret < 0) {
        return ret;
    }

    reg &= ~BQ25628E_VINDPM_MASK;
    reg |= FIELD_PREP(BQ25628E_VINDPM_MASK, vindpm);

    return bq25628e_write16(dev, BQ25628E_REG_INPUT_VOLTAGE_LOW, reg);
}

static int bq25628e_get_input_voltage_limit(const struct device* dev, uint32_t* voltage_uv) {
    uint16_t reg;
    uint16_t vindpm;
    int ret;

    ret = bq25628e_read16(dev, BQ25628E_REG_INPUT_VOLTAGE_LOW, &reg);
    if (ret < 0) {
        return ret;
    }

    vindpm      = FIELD_GET(BQ25628E_VINDPM_MASK, reg);
    *voltage_uv = vindpm * BQ25628E_VINDPM_STEP_UV;

    return 0;
}

static int bq25628e_set_precharge_current_limit(const struct device* dev, uint32_t current_ua) {
    uint16_t reg;
    uint16_t iprechg;
    int ret;

    current_ua = CLAMP(current_ua, BQ25628E_IPRECHG_MIN_UA, BQ25628E_IPRECHG_MAX_UA);

    iprechg = current_ua / BQ25628E_IPRECHG_STEP_UA;

    ret = bq25628e_read16(dev, BQ25628E_REG_PRECHARGE_CONTROL_LOW, &reg);
    if (ret < 0) {
        return ret;
    }

    reg &= ~BQ25628E_IPRECHG_MASK;
    reg |= FIELD_PREP(BQ25628E_IPRECHG_MASK, iprechg);

    return bq25628e_write16(dev, BQ25628E_REG_PRECHARGE_CONTROL_LOW, reg);
}

static int bq25628e_get_precharge_current_limit(const struct device* dev, uint32_t* current_ua) {
    uint16_t reg;
    uint16_t iprechg;
    int ret;

    ret = bq25628e_read16(dev, BQ25628E_REG_PRECHARGE_CONTROL_LOW, &reg);
    if (ret < 0) {
        return ret;
    }

    iprechg     = FIELD_GET(BQ25628E_IPRECHG_MASK, reg);
    *current_ua = iprechg * BQ25628E_IPRECHG_STEP_UA;

    return 0;
}

static int bq25628e_set_termination_current_limit(const struct device* dev, uint32_t current_ua) {
    uint16_t reg;
    uint16_t iterm;
    int ret;

    current_ua = CLAMP(current_ua, BQ25628E_ITERM_MIN_UA, BQ25628E_ITERM_MAX_UA);

    iterm = current_ua / BQ25628E_ITERM_STEP_UA;

    ret = bq25628e_read16(dev, BQ25628E_REG_TERMINATION_CONTROL_LOW, &reg);
    if (ret < 0) {
        return ret;
    }

    reg &= ~BQ25628E_ITERM_MASK;
    reg |= FIELD_PREP(BQ25628E_ITERM_MASK, iterm);

    return bq25628e_write16(dev, BQ25628E_REG_TERMINATION_CONTROL_LOW, reg);
}

static int bq25628e_get_termination_current_limit(const struct device* dev, uint32_t* current_ua) {
    uint16_t reg;
    uint16_t iterm;
    int ret;

    ret = bq25628e_read16(dev, BQ25628E_REG_TERMINATION_CONTROL_LOW, &reg);
    if (ret < 0) {
        return ret;
    }

    iterm       = FIELD_GET(BQ25628E_ITERM_MASK, reg);
    *current_ua = iterm * BQ25628E_ITERM_STEP_UA;

    return 0;
}

static int bq25628e_update_bits8(const struct device* dev, uint8_t reg, uint8_t mask,
                                 uint8_t value) {
    uint8_t regval;
    int ret;

    ret = bq25628e_read8(dev, reg, &regval);
    if (ret < 0) {
        return ret;
    }

    regval &= ~mask;
    regval |= value & mask;

    return bq25628e_write8(dev, reg, regval);
}

static int bq25628e_set_q1_fullon(const struct device* dev, bool enable) {
    return bq25628e_update_bits8(dev, BQ25628E_REG_CHARGE_CONTROL, BQ25628E_Q1_FULLON_MASK,
                                 enable ? BQ25628E_Q1_FULLON_MASK : 0);
}

static int bq25628e_get_q1_fullon(const struct device* dev, bool* enable) {
    uint8_t reg;
    int ret;

    ret = bq25628e_read8(dev, BQ25628E_REG_CHARGE_CONTROL, &reg);
    if (ret < 0) {
        return ret;
    }

    *enable = (reg & BQ25628E_Q1_FULLON_MASK) != 0;

    return 0;
}

static int bq25628e_set_q4_fullon(const struct device* dev, bool enable) {
    return bq25628e_update_bits8(dev, BQ25628E_REG_CHARGE_CONTROL, BQ25628E_Q4_FULLON_MASK,
                                 enable ? BQ25628E_Q4_FULLON_MASK : 0);
}

static int bq25628e_get_q4_fullon(const struct device* dev, bool* enable) {
    uint8_t reg;
    int ret;

    ret = bq25628e_read8(dev, BQ25628E_REG_CHARGE_CONTROL, &reg);
    if (ret < 0) {
        return ret;
    }

    *enable = (reg & BQ25628E_Q4_FULLON_MASK) != 0;

    return 0;
}

static int bq25628e_set_trickle_current(const struct device* dev, uint32_t current_ua) {
    uint8_t value;

    switch (current_ua) {
    case BQ25628E_ITRICKLE_10MA_UA:
        value = 0;
        break;
    case BQ25628E_ITRICKLE_40MA_UA:
        value = BQ25628E_ITRICKLE_MASK;
        break;
    default:
        return -EINVAL;
    }

    return bq25628e_update_bits8(dev, BQ25628E_REG_CHARGE_CONTROL, BQ25628E_ITRICKLE_MASK, value);
}

static int bq25628e_get_trickle_current(const struct device* dev, uint32_t* current_ua) {
    uint8_t reg;
    int ret;

    ret = bq25628e_read8(dev, BQ25628E_REG_CHARGE_CONTROL, &reg);
    if (ret < 0) {
        return ret;
    }

    *current_ua =
        (reg & BQ25628E_ITRICKLE_MASK) ? BQ25628E_ITRICKLE_40MA_UA : BQ25628E_ITRICKLE_10MA_UA;

    return 0;
}

static int bq25628e_set_topoff_timer(const struct device* dev, uint32_t minutes) {
    uint8_t field;

    switch (minutes) {
    case 0:
        field = 0;
        break;
    case 17:
        field = 1;
        break;
    case 35:
        field = 2;
        break;
    case 52:
        field = 3;
        break;
    default:
        return -EINVAL;
    }

    return bq25628e_update_bits8(dev, BQ25628E_REG_CHARGE_CONTROL, BQ25628E_TOPOFF_TMR_MASK,
                                 FIELD_PREP(BQ25628E_TOPOFF_TMR_MASK, field));
}

static int bq25628e_get_topoff_timer(const struct device* dev, uint32_t* minutes) {
    uint8_t reg;
    uint8_t field;
    int ret;

    ret = bq25628e_read8(dev, BQ25628E_REG_CHARGE_CONTROL, &reg);
    if (ret < 0) {
        return ret;
    }

    field = FIELD_GET(BQ25628E_TOPOFF_TMR_MASK, reg);

    switch (field) {
    case 0:
        *minutes = 0;
        break;
    case 1:
        *minutes = 17;
        break;
    case 2:
        *minutes = 35;
        break;
    case 3:
        *minutes = 52;
        break;
    default:
        return -EINVAL;
    }

    return 0;
}

static int bq25628e_set_termination_enable(const struct device* dev, bool enable) {
    return bq25628e_update_bits8(dev, BQ25628E_REG_CHARGE_CONTROL, BQ25628E_EN_TERM_MASK,
                                 enable ? BQ25628E_EN_TERM_MASK : 0);
}

static int bq25628e_get_termination_enable(const struct device* dev, bool* enable) {
    uint8_t reg;
    int ret;

    ret = bq25628e_read8(dev, BQ25628E_REG_CHARGE_CONTROL, &reg);
    if (ret < 0) {
        return ret;
    }

    *enable = (reg & BQ25628E_EN_TERM_MASK) != 0;

    return 0;
}

static int bq25628e_set_vindpm_bat_track(const struct device* dev, bool enable) {
    return bq25628e_update_bits8(dev, BQ25628E_REG_CHARGE_CONTROL, BQ25628E_VINDPM_BAT_TRACK_MASK,
                                 enable ? BQ25628E_VINDPM_BAT_TRACK_MASK : 0);
}

static int bq25628e_get_vindpm_bat_track(const struct device* dev, bool* enable) {
    uint8_t reg;
    int ret;

    ret = bq25628e_read8(dev, BQ25628E_REG_CHARGE_CONTROL, &reg);
    if (ret < 0) {
        return ret;
    }

    *enable = (reg & BQ25628E_VINDPM_BAT_TRACK_MASK) != 0;

    return 0;
}

static int bq25628e_set_recharge_threshold_offset(const struct device* dev, uint32_t offset_uv) {
    uint8_t value;

    switch (offset_uv) {
    case BQ25628E_VRECHG_100MV_UV:
        value = 0;
        break;
    case BQ25628E_VRECHG_200MV_UV:
        value = BQ25628E_VRECHG_MASK;
        break;
    default:
        return -EINVAL;
    }

    return bq25628e_update_bits8(dev, BQ25628E_REG_CHARGE_CONTROL, BQ25628E_VRECHG_MASK, value);
}

static int bq25628e_get_recharge_threshold_offset(const struct device* dev, uint32_t* offset_uv) {
    uint8_t reg;
    int ret;

    ret = bq25628e_read8(dev, BQ25628E_REG_CHARGE_CONTROL, &reg);
    if (ret < 0) {
        return ret;
    }

    *offset_uv = (reg & BQ25628E_VRECHG_MASK) ? BQ25628E_VRECHG_200MV_UV : BQ25628E_VRECHG_100MV_UV;

    return 0;
}

static int bq25628e_set_stat_pin_disabled(const struct device* dev, bool disabled) {
    return bq25628e_update_bits8(dev, BQ25628E_REG_CHARGE_TIMER_CONTROL, BQ25628E_DIS_STAT_MASK,
                                 disabled ? BQ25628E_DIS_STAT_MASK : 0);
}

static int bq25628e_get_stat_pin_disabled(const struct device* dev, bool* disabled) {
    uint8_t reg;
    int ret;

    ret = bq25628e_read8(dev, BQ25628E_REG_CHARGE_TIMER_CONTROL, &reg);
    if (ret < 0) {
        return ret;
    }

    *disabled = (reg & BQ25628E_DIS_STAT_MASK) != 0;

    return 0;
}

static int bq25628e_set_timer_2x_enabled(const struct device* dev, bool enabled) {
    return bq25628e_update_bits8(dev, BQ25628E_REG_CHARGE_TIMER_CONTROL, BQ25628E_TMR2X_EN_MASK,
                                 enabled ? BQ25628E_TMR2X_EN_MASK : 0);
}

static int bq25628e_get_timer_2x_enabled(const struct device* dev, bool* enabled) {
    uint8_t reg;
    int ret;

    ret = bq25628e_read8(dev, BQ25628E_REG_CHARGE_TIMER_CONTROL, &reg);
    if (ret < 0) {
        return ret;
    }

    *enabled = (reg & BQ25628E_TMR2X_EN_MASK) != 0;

    return 0;
}

static int bq25628e_set_safety_timers_enabled(const struct device* dev, bool enabled) {
    return bq25628e_update_bits8(dev, BQ25628E_REG_CHARGE_TIMER_CONTROL,
                                 BQ25628E_EN_SAFETY_TMRS_MASK,
                                 enabled ? BQ25628E_EN_SAFETY_TMRS_MASK : 0);
}

static int bq25628e_get_safety_timers_enabled(const struct device* dev, bool* enabled) {
    uint8_t reg;
    int ret;

    ret = bq25628e_read8(dev, BQ25628E_REG_CHARGE_TIMER_CONTROL, &reg);
    if (ret < 0) {
        return ret;
    }

    *enabled = (reg & BQ25628E_EN_SAFETY_TMRS_MASK) != 0;

    return 0;
}

static int bq25628e_set_precharge_timer(const struct device* dev, uint32_t seconds) {
    uint8_t value;

    switch (seconds) {
    case BQ25628E_PRECHG_TMR_2P5H_SEC:
        value = 0;
        break;
    case BQ25628E_PRECHG_TMR_0P62H_SEC:
        value = BQ25628E_PRECHG_TMR_MASK;
        break;
    default:
        return -EINVAL;
    }

    return bq25628e_update_bits8(dev, BQ25628E_REG_CHARGE_TIMER_CONTROL, BQ25628E_PRECHG_TMR_MASK,
                                 value);
}

static int bq25628e_get_precharge_timer(const struct device* dev, uint32_t* seconds) {
    uint8_t reg;
    int ret;

    ret = bq25628e_read8(dev, BQ25628E_REG_CHARGE_TIMER_CONTROL, &reg);
    if (ret < 0) {
        return ret;
    }

    *seconds = (reg & BQ25628E_PRECHG_TMR_MASK) ? BQ25628E_PRECHG_TMR_0P62H_SEC
                                                : BQ25628E_PRECHG_TMR_2P5H_SEC;

    return 0;
}

static int bq25628e_set_fast_charge_timer(const struct device* dev, uint32_t seconds) {
    uint8_t value;

    switch (seconds) {
    case BQ25628E_CHG_TMR_14P5H_SEC:
        value = 0;
        break;
    case BQ25628E_CHG_TMR_28H_SEC:
        value = BQ25628E_CHG_TMR_MASK;
        break;
    default:
        return -EINVAL;
    }

    return bq25628e_update_bits8(dev, BQ25628E_REG_CHARGE_TIMER_CONTROL, BQ25628E_CHG_TMR_MASK,
                                 value);
}

static int bq25628e_get_fast_charge_timer(const struct device* dev, uint32_t* seconds) {
    uint8_t reg;
    int ret;

    ret = bq25628e_read8(dev, BQ25628E_REG_CHARGE_TIMER_CONTROL, &reg);
    if (ret < 0) {
        return ret;
    }

    *seconds =
        (reg & BQ25628E_CHG_TMR_MASK) ? BQ25628E_CHG_TMR_28H_SEC : BQ25628E_CHG_TMR_14P5H_SEC;

    return 0;
}

static int bq25628e_set_auto_battery_discharge_enabled(const struct device* dev, bool enabled) {
    return bq25628e_update_bits8(dev, BQ25628E_REG_CHARGER_CONTROL_0, BQ25628E_EN_AUTO_IBATDIS_MASK,
                                 enabled ? BQ25628E_EN_AUTO_IBATDIS_MASK : 0);
}

static int bq25628e_get_auto_battery_discharge_enabled(const struct device* dev, bool* enabled) {
    uint8_t reg;
    int ret;

    ret = bq25628e_read8(dev, BQ25628E_REG_CHARGER_CONTROL_0, &reg);
    if (ret < 0) {
        return ret;
    }

    *enabled = (reg & BQ25628E_EN_AUTO_IBATDIS_MASK) != 0;

    return 0;
}

static int bq25628e_set_force_battery_discharge(const struct device* dev, bool enabled) {
    return bq25628e_update_bits8(dev, BQ25628E_REG_CHARGER_CONTROL_0, BQ25628E_FORCE_IBATDIS_MASK,
                                 enabled ? BQ25628E_FORCE_IBATDIS_MASK : 0);
}

static int bq25628e_get_force_battery_discharge(const struct device* dev, bool* enabled) {
    uint8_t reg;
    int ret;

    ret = bq25628e_read8(dev, BQ25628E_REG_CHARGER_CONTROL_0, &reg);
    if (ret < 0) {
        return ret;
    }

    *enabled = (reg & BQ25628E_FORCE_IBATDIS_MASK) != 0;

    return 0;
}

static int bq25628e_set_charge_enabled(const struct device* dev, bool enabled) {
    return bq25628e_update_bits8(dev, BQ25628E_REG_CHARGER_CONTROL_0, BQ25628E_EN_CHG_MASK,
                                 enabled ? BQ25628E_EN_CHG_MASK : 0);
}

static int bq25628e_get_charge_enabled(const struct device* dev, bool* enabled) {
    uint8_t reg;
    int ret;

    ret = bq25628e_read8(dev, BQ25628E_REG_CHARGER_CONTROL_0, &reg);
    if (ret < 0) {
        return ret;
    }

    *enabled = (reg & BQ25628E_EN_CHG_MASK) != 0;

    return 0;
}

static int bq25628e_set_hiz_enabled(const struct device* dev, bool enabled) {
    return bq25628e_update_bits8(dev, BQ25628E_REG_CHARGER_CONTROL_0, BQ25628E_EN_HIZ_MASK,
                                 enabled ? BQ25628E_EN_HIZ_MASK : 0);
}

static int bq25628e_get_hiz_enabled(const struct device* dev, bool* enabled) {
    uint8_t reg;
    int ret;

    ret = bq25628e_read8(dev, BQ25628E_REG_CHARGER_CONTROL_0, &reg);
    if (ret < 0) {
        return ret;
    }

    *enabled = (reg & BQ25628E_EN_HIZ_MASK) != 0;

    return 0;
}

static int bq25628e_set_force_pmid_discharge(const struct device* dev, bool enabled) {
    return bq25628e_update_bits8(dev, BQ25628E_REG_CHARGER_CONTROL_0, BQ25628E_FORCE_PMID_DIS_MASK,
                                 enabled ? BQ25628E_FORCE_PMID_DIS_MASK : 0);
}

static int bq25628e_get_force_pmid_discharge(const struct device* dev, bool* enabled) {
    uint8_t reg;
    int ret;

    ret = bq25628e_read8(dev, BQ25628E_REG_CHARGER_CONTROL_0, &reg);
    if (ret < 0) {
        return ret;
    }

    *enabled = (reg & BQ25628E_FORCE_PMID_DIS_MASK) != 0;

    return 0;
}

static int bq25628e_reset_watchdog(const struct device* dev) {
    return bq25628e_update_bits8(dev, BQ25628E_REG_CHARGER_CONTROL_0, BQ25628E_WD_RST_MASK,
                                 BQ25628E_WD_RST_MASK);
}

static int bq25628e_set_watchdog_timer(const struct device* dev, uint32_t seconds) {
    uint8_t field;

    switch (seconds) {
    case BQ25628E_WATCHDOG_DISABLED_SEC:
        field = 0;
        break;
    case BQ25628E_WATCHDOG_50_SEC:
        field = 1;
        break;
    case BQ25628E_WATCHDOG_100_SEC:
        field = 2;
        break;
    case BQ25628E_WATCHDOG_200_SEC:
        field = 3;
        break;
    default:
        return -EINVAL;
    }

    return bq25628e_update_bits8(dev, BQ25628E_REG_CHARGER_CONTROL_0, BQ25628E_WATCHDOG_MASK,
                                 FIELD_PREP(BQ25628E_WATCHDOG_MASK, field));
}

static int bq25628e_get_watchdog_timer(const struct device* dev, uint32_t* seconds) {
    uint8_t reg;
    uint8_t field;
    int ret;

    ret = bq25628e_read8(dev, BQ25628E_REG_CHARGER_CONTROL_0, &reg);
    if (ret < 0) {
        return ret;
    }

    field = FIELD_GET(BQ25628E_WATCHDOG_MASK, reg);

    switch (field) {
    case 0:
        *seconds = BQ25628E_WATCHDOG_DISABLED_SEC;
        break;
    case 1:
        *seconds = BQ25628E_WATCHDOG_50_SEC;
        break;
    case 2:
        *seconds = BQ25628E_WATCHDOG_100_SEC;
        break;
    case 3:
        *seconds = BQ25628E_WATCHDOG_200_SEC;
        break;
    default:
        return -EINVAL;
    }

    return 0;
}

static int bq25628e_reset_registers(const struct device* dev) {
    return bq25628e_update_bits8(dev, BQ25628E_REG_CHARGER_CONTROL_1, BQ25628E_REG_RST_MASK,
                                 BQ25628E_REG_RST_MASK);
}

static int bq25628e_set_thermal_regulation_threshold(const struct device* dev, uint32_t temp_c) {
    uint8_t value;

    switch (temp_c) {
    case BQ25628E_TREG_60C:
        value = 0;
        break;
    case BQ25628E_TREG_120C:
        value = BQ25628E_TREG_MASK;
        break;
    default:
        return -EINVAL;
    }

    return bq25628e_update_bits8(dev, BQ25628E_REG_CHARGER_CONTROL_1, BQ25628E_TREG_MASK, value);
}

static int bq25628e_get_thermal_regulation_threshold(const struct device* dev, uint32_t* temp_c) {
    uint8_t reg;
    int ret;

    ret = bq25628e_read8(dev, BQ25628E_REG_CHARGER_CONTROL_1, &reg);
    if (ret < 0) {
        return ret;
    }

    *temp_c = (reg & BQ25628E_TREG_MASK) ? BQ25628E_TREG_120C : BQ25628E_TREG_60C;

    return 0;
}

static int bq25628e_set_converter_frequency(const struct device* dev, uint32_t freq_hz) {
    uint8_t field;

    switch (freq_hz) {
    case BQ25628E_CONV_FREQ_1P5MHZ_HZ:
        field = 0;
        break;
    case BQ25628E_CONV_FREQ_1P35MHZ_HZ:
        field = 1;
        break;
    case BQ25628E_CONV_FREQ_1P65MHZ_HZ:
        field = 2;
        break;
    default:
        return -EINVAL;
    }

    return bq25628e_update_bits8(dev, BQ25628E_REG_CHARGER_CONTROL_1, BQ25628E_SET_CONV_FREQ_MASK,
                                 FIELD_PREP(BQ25628E_SET_CONV_FREQ_MASK, field));
}

static int bq25628e_get_converter_frequency(const struct device* dev, uint32_t* freq_hz) {
    uint8_t reg;
    uint8_t field;
    int ret;

    ret = bq25628e_read8(dev, BQ25628E_REG_CHARGER_CONTROL_1, &reg);
    if (ret < 0) {
        return ret;
    }

    field = FIELD_GET(BQ25628E_SET_CONV_FREQ_MASK, reg);

    switch (field) {
    case 0:
        *freq_hz = BQ25628E_CONV_FREQ_1P5MHZ_HZ;
        break;
    case 1:
        *freq_hz = BQ25628E_CONV_FREQ_1P35MHZ_HZ;
        break;
    case 2:
        *freq_hz = BQ25628E_CONV_FREQ_1P65MHZ_HZ;
        break;
    default:
        return -EINVAL;
    }

    return 0;
}

static int bq25628e_set_converter_drive_strength(const struct device* dev,
                                                 enum bq25628e_converter_drive_strength strength) {
    switch (strength) {
    case BQ25628E_CONV_STRN_WEAK:
    case BQ25628E_CONV_STRN_NORMAL:
    case BQ25628E_CONV_STRN_STRONG:
        return bq25628e_update_bits8(dev, BQ25628E_REG_CHARGER_CONTROL_1,
                                     BQ25628E_SET_CONV_STRN_MASK,
                                     FIELD_PREP(BQ25628E_SET_CONV_STRN_MASK, strength));
    default:
        return -EINVAL;
    }
}

static int bq25628e_get_converter_drive_strength(const struct device* dev,
                                                 enum bq25628e_converter_drive_strength* strength) {
    uint8_t reg;
    uint8_t field;
    int ret;

    ret = bq25628e_read8(dev, BQ25628E_REG_CHARGER_CONTROL_1, &reg);
    if (ret < 0) {
        return ret;
    }

    field = FIELD_GET(BQ25628E_SET_CONV_STRN_MASK, reg);

    switch (field) {
    case BQ25628E_CONV_STRN_WEAK:
    case BQ25628E_CONV_STRN_NORMAL:
    case BQ25628E_CONV_STRN_STRONG:
        *strength = field;
        break;
    default:
        return -EINVAL;
    }

    return 0;
}

static int bq25628e_set_vbus_ovp_threshold(const struct device* dev, uint32_t voltage_uv) {
    uint8_t value;

    switch (voltage_uv) {
    case BQ25628E_VBUS_OVP_6P3V_UV:
        value = 0;
        break;
    case BQ25628E_VBUS_OVP_18P5V_UV:
        value = BQ25628E_VBUS_OVP_MASK;
        break;
    default:
        return -EINVAL;
    }

    return bq25628e_update_bits8(dev, BQ25628E_REG_CHARGER_CONTROL_1, BQ25628E_VBUS_OVP_MASK,
                                 value);
}

static int bq25628e_get_vbus_ovp_threshold(const struct device* dev, uint32_t* voltage_uv) {
    uint8_t reg;
    int ret;

    ret = bq25628e_read8(dev, BQ25628E_REG_CHARGER_CONTROL_1, &reg);
    if (ret < 0) {
        return ret;
    }

    *voltage_uv =
        (reg & BQ25628E_VBUS_OVP_MASK) ? BQ25628E_VBUS_OVP_18P5V_UV : BQ25628E_VBUS_OVP_6P3V_UV;

    return 0;
}

static int bq25628e_set_pfm_forward_buck_disabled(const struct device* dev, bool disabled) {
    return bq25628e_update_bits8(dev, BQ25628E_REG_CHARGER_CONTROL_2, BQ25628E_PFM_FWD_DIS_MASK,
                                 disabled ? BQ25628E_PFM_FWD_DIS_MASK : 0);
}

static int bq25628e_get_pfm_forward_buck_disabled(const struct device* dev, bool* disabled) {
    uint8_t reg;
    int ret;

    ret = bq25628e_read8(dev, BQ25628E_REG_CHARGER_CONTROL_2, &reg);
    if (ret < 0) {
        return ret;
    }

    *disabled = (reg & BQ25628E_PFM_FWD_DIS_MASK) != 0;

    return 0;
}

static int bq25628e_set_batfet_ctrl_with_vbus_enabled(const struct device* dev, bool enabled) {
    return bq25628e_update_bits8(dev, BQ25628E_REG_CHARGER_CONTROL_2,
                                 BQ25628E_BATFET_CTRL_WVBUS_MASK,
                                 enabled ? BQ25628E_BATFET_CTRL_WVBUS_MASK : 0);
}

static int bq25628e_get_batfet_ctrl_with_vbus_enabled(const struct device* dev, bool* enabled) {
    uint8_t reg;
    int ret;

    ret = bq25628e_read8(dev, BQ25628E_REG_CHARGER_CONTROL_2, &reg);
    if (ret < 0) {
        return ret;
    }

    *enabled = (reg & BQ25628E_BATFET_CTRL_WVBUS_MASK) != 0;

    return 0;
}

static int bq25628e_set_batfet_delay(const struct device* dev, uint32_t delay_ms) {
    uint8_t value;

    switch (delay_ms) {
    case BQ25628E_BATFET_DLY_25_MS:
        value = 0;
        break;
    case BQ25628E_BATFET_DLY_12P5_SEC_MS:
        value = BQ25628E_BATFET_DLY_MASK;
        break;
    default:
        return -EINVAL;
    }

    return bq25628e_update_bits8(dev, BQ25628E_REG_CHARGER_CONTROL_2, BQ25628E_BATFET_DLY_MASK,
                                 value);
}

static int bq25628e_get_batfet_delay(const struct device* dev, uint32_t* delay_ms) {
    uint8_t reg;
    int ret;

    ret = bq25628e_read8(dev, BQ25628E_REG_CHARGER_CONTROL_2, &reg);
    if (ret < 0) {
        return ret;
    }

    *delay_ms = (reg & BQ25628E_BATFET_DLY_MASK) ? BQ25628E_BATFET_DLY_12P5_SEC_MS
                                                 : BQ25628E_BATFET_DLY_25_MS;

    return 0;
}

static int bq25628e_set_batfet_control(const struct device* dev, enum bq25628e_batfet_ctrl mode) {
    switch (mode) {
    case BQ25628E_BATFET_CTRL_NORMAL:
    case BQ25628E_BATFET_CTRL_SHUTDOWN:
    case BQ25628E_BATFET_CTRL_SHIP:
    case BQ25628E_BATFET_CTRL_SYSTEM_POWER_RESET:
        return bq25628e_update_bits8(dev, BQ25628E_REG_CHARGER_CONTROL_2, BQ25628E_BATFET_CTRL_MASK,
                                     FIELD_PREP(BQ25628E_BATFET_CTRL_MASK, mode));
    default:
        return -EINVAL;
    }
}

static int bq25628e_get_batfet_control(const struct device* dev, enum bq25628e_batfet_ctrl* mode) {
    uint8_t reg;
    uint8_t field;
    int ret;

    ret = bq25628e_read8(dev, BQ25628E_REG_CHARGER_CONTROL_2, &reg);
    if (ret < 0) {
        return ret;
    }

    field = FIELD_GET(BQ25628E_BATFET_CTRL_MASK, reg);
    *mode = (enum bq25628e_batfet_ctrl)field;

    return 0;
}

static int bq25628e_get_adc_done_status(const struct device* dev, bool* done) {
    uint8_t reg;
    int ret;

    ret = bq25628e_read8(dev, BQ25628E_REG_CHARGER_STATUS_0, &reg);
    if (ret < 0) {
        return ret;
    }

    *done = (reg & BQ25628E_ADC_DONE_STAT_MASK) != 0;

    return 0;
}

static int bq25628e_get_thermal_regulation_status(const struct device* dev, bool* active) {
    uint8_t reg;
    int ret;

    ret = bq25628e_read8(dev, BQ25628E_REG_CHARGER_STATUS_0, &reg);
    if (ret < 0) {
        return ret;
    }

    *active = (reg & BQ25628E_TREG_STAT_MASK) != 0;

    return 0;
}

static int bq25628e_get_vsys_regulation_status(const struct device* dev, bool* active) {
    uint8_t reg;
    int ret;

    ret = bq25628e_read8(dev, BQ25628E_REG_CHARGER_STATUS_0, &reg);
    if (ret < 0) {
        return ret;
    }

    *active = (reg & BQ25628E_VSYS_STAT_MASK) != 0;

    return 0;
}

static int bq25628e_get_iindpm_status(const struct device* dev, bool* active) {
    uint8_t reg;
    int ret;

    ret = bq25628e_read8(dev, BQ25628E_REG_CHARGER_STATUS_0, &reg);
    if (ret < 0) {
        return ret;
    }

    *active = (reg & BQ25628E_IINDPM_STAT_MASK) != 0;

    return 0;
}

static int bq25628e_get_vindpm_status(const struct device* dev, bool* active) {
    uint8_t reg;
    int ret;

    ret = bq25628e_read8(dev, BQ25628E_REG_CHARGER_STATUS_0, &reg);
    if (ret < 0) {
        return ret;
    }

    *active = (reg & BQ25628E_VINDPM_STAT_MASK) != 0;

    return 0;
}

static int bq25628e_get_safety_timer_expired_status(const struct device* dev, bool* expired) {
    uint8_t reg;
    int ret;

    ret = bq25628e_read8(dev, BQ25628E_REG_CHARGER_STATUS_0, &reg);
    if (ret < 0) {
        return ret;
    }

    *expired = (reg & BQ25628E_SAFETY_TMR_STAT_MASK) != 0;

    return 0;
}

static int bq25628e_get_watchdog_expired_status(const struct device* dev, bool* expired) {
    uint8_t reg;
    int ret;

    ret = bq25628e_read8(dev, BQ25628E_REG_CHARGER_STATUS_0, &reg);
    if (ret < 0) {
        return ret;
    }

    *expired = (reg & BQ25628E_WD_STAT_MASK) != 0;

    return 0;
}

static int bq25628e_get_charge_status(const struct device* dev,
                                      enum bq25628e_charge_status* status) {
    uint8_t reg;
    uint8_t field;
    int ret;

    ret = bq25628e_read8(dev, BQ25628E_REG_CHARGER_STATUS_1, &reg);
    if (ret < 0) {
        return ret;
    }

    field = FIELD_GET(BQ25628E_CHG_STAT_MASK, reg);

    switch (field) {
    case BQ25628E_CHG_STAT_NOT_CHARGING:
    case BQ25628E_CHG_STAT_TRICKLE_PRECHG_CC:
    case BQ25628E_CHG_STAT_TAPER_CV:
    case BQ25628E_CHG_STAT_TOPOFF_TIMER:
        *status = (enum bq25628e_charge_status)field;
        return 0;
    default:
        return -EINVAL;
    }
}

static int bq25628e_get_vbus_status(const struct device* dev, enum bq25628e_vbus_status* status) {
    uint8_t reg;
    uint8_t field;
    int ret;

    ret = bq25628e_read8(dev, BQ25628E_REG_CHARGER_STATUS_1, &reg);
    if (ret < 0) {
        return ret;
    }

    field = FIELD_GET(BQ25628E_VBUS_STAT_MASK, reg);

    switch (field) {
    case BQ25628E_VBUS_STAT_NOT_POWERED:
    case BQ25628E_VBUS_STAT_UNKNOWN_ADAPTER:
        *status = (enum bq25628e_vbus_status)field;
        return 0;
    default:
        return -EINVAL;
    }
}

static int bq25628e_get_flag0_bit(const struct device* dev, uint8_t mask, bool* active) {
    uint8_t reg;
    int ret;

    ret = bq25628e_read8(dev, BQ25628E_REG_CHARGER_FLAG_0, &reg);
    if (ret < 0) {
        return ret;
    }

    *active = (reg & mask) != 0;

    return 0;
}

static int bq25628e_get_adc_done_flag(const struct device* dev, bool* flag) {
    return bq25628e_get_flag0_bit(dev, BQ25628E_ADC_DONE_FLAG_MASK, flag);
}

static int bq25628e_get_thermal_regulation_flag(const struct device* dev, bool* flag) {
    return bq25628e_get_flag0_bit(dev, BQ25628E_TREG_FLAG_MASK, flag);
}

static int bq25628e_get_vsys_regulation_flag(const struct device* dev, bool* flag) {
    return bq25628e_get_flag0_bit(dev, BQ25628E_VSYS_FLAG_MASK, flag);
}

static int bq25628e_get_iindpm_flag(const struct device* dev, bool* flag) {
    return bq25628e_get_flag0_bit(dev, BQ25628E_IINDPM_FLAG_MASK, flag);
}

static int bq25628e_get_vindpm_flag(const struct device* dev, bool* flag) {
    return bq25628e_get_flag0_bit(dev, BQ25628E_VINDPM_FLAG_MASK, flag);
}

static int bq25628e_get_safety_timer_expired_flag(const struct device* dev, bool* flag) {
    return bq25628e_get_flag0_bit(dev, BQ25628E_SAFETY_TMR_FLAG_MASK, flag);
}

static int bq25628e_get_watchdog_expired_flag(const struct device* dev, bool* flag) {
    return bq25628e_get_flag0_bit(dev, BQ25628E_WD_FLAG_MASK, flag);
}

static int bq25628e_charge_enable(const struct device* dev, const bool enable) {
    return bq25628e_set_charge_enabled(dev, enable);
}

static int bq25628e_get_online_prop(const struct device* dev, enum charger_online* online) {
    enum bq25628e_vbus_status vbus;
    int ret;

    ret = bq25628e_get_vbus_status(dev, &vbus);
    if (ret < 0) {
        return ret;
    }

    switch (vbus) {
    case BQ25628E_VBUS_STAT_NOT_POWERED:
        *online = CHARGER_ONLINE_OFFLINE;
        return 0;
    case BQ25628E_VBUS_STAT_UNKNOWN_ADAPTER:
        *online = CHARGER_ONLINE_FIXED;
        return 0;
    default:
        return -EINVAL;
    }
}

static int bq25628e_get_status_prop(const struct device* dev, enum charger_status* status) {
    enum bq25628e_charge_status chg;
    enum charger_online online;
    int ret;

    ret = bq25628e_get_charge_status(dev, &chg);
    if (ret < 0) {
        return ret;
    }

    switch (chg) {
    case BQ25628E_CHG_STAT_NOT_CHARGING:
        ret = bq25628e_get_online_prop(dev, &online);
        if (ret < 0) {
            return ret;
        }

        *status = online == CHARGER_ONLINE_OFFLINE ? CHARGER_STATUS_DISCHARGING
                                                   : CHARGER_STATUS_NOT_CHARGING;
        return 0;

    case BQ25628E_CHG_STAT_TRICKLE_PRECHG_CC:
    case BQ25628E_CHG_STAT_TAPER_CV:
    case BQ25628E_CHG_STAT_TOPOFF_TIMER:
        *status = CHARGER_STATUS_CHARGING;
        return 0;

    default:
        return -EINVAL;
    }
}

static int bq25628e_get_charge_type_prop(const struct device* dev,
                                         enum charger_charge_type* charge_type) {
    enum bq25628e_charge_status chg;
    int ret;

    ret = bq25628e_get_charge_status(dev, &chg);
    if (ret < 0) {
        return ret;
    }

    switch (chg) {
    case BQ25628E_CHG_STAT_NOT_CHARGING:
        *charge_type = CHARGER_CHARGE_TYPE_NONE;
        return 0;

    case BQ25628E_CHG_STAT_TRICKLE_PRECHG_CC:
        *charge_type = CHARGER_CHARGE_TYPE_TRICKLE;
        return 0;

    case BQ25628E_CHG_STAT_TAPER_CV:
    case BQ25628E_CHG_STAT_TOPOFF_TIMER:
        *charge_type = CHARGER_CHARGE_TYPE_FAST;
        return 0;

    default:
        return -EINVAL;
    }
}

static int bq25628e_get_health_prop(const struct device* dev, enum charger_health* health) {
    bool active;
    int ret;

    ret = bq25628e_get_watchdog_expired_status(dev, &active);
    if (ret < 0) {
        return ret;
    }
    if (active) {
        *health = CHARGER_HEALTH_WATCHDOG_TIMER_EXPIRE;
        return 0;
    }

    ret = bq25628e_get_safety_timer_expired_status(dev, &active);
    if (ret < 0) {
        return ret;
    }
    if (active) {
        *health = CHARGER_HEALTH_SAFETY_TIMER_EXPIRE;
        return 0;
    }

    ret = bq25628e_get_thermal_regulation_status(dev, &active);
    if (ret < 0) {
        return ret;
    }
    if (active) {
        *health = CHARGER_HEALTH_OVERHEAT;
        return 0;
    }

    *health = CHARGER_HEALTH_GOOD;
    return 0;
}

static int bq25628e_get_prop(const struct device* dev, charger_prop_t prop,
                             union charger_propval* value) {
    if (value == NULL) {
        return -EINVAL;
    }

    switch (prop) {
    case CHARGER_PROP_ONLINE:
        return bq25628e_get_online_prop(dev, &value->online);

    case CHARGER_PROP_STATUS:
        return bq25628e_get_status_prop(dev, &value->status);

    case CHARGER_PROP_CHARGE_TYPE:
        return bq25628e_get_charge_type_prop(dev, &value->charge_type);

    case CHARGER_PROP_HEALTH:
        return bq25628e_get_health_prop(dev, &value->health);

    case CHARGER_PROP_CONSTANT_CHARGE_CURRENT_UA:
        return bq25628e_get_charge_current_limit(dev, &value->const_charge_current_ua);

    case CHARGER_PROP_PRECHARGE_CURRENT_UA:
        return bq25628e_get_precharge_current_limit(dev, &value->precharge_current_ua);

    case CHARGER_PROP_CHARGE_TERM_CURRENT_UA:
        return bq25628e_get_termination_current_limit(dev, &value->charge_term_current_ua);

    case CHARGER_PROP_CONSTANT_CHARGE_VOLTAGE_UV:
        return bq25628e_get_charge_voltage_limit(dev, &value->const_charge_voltage_uv);

    case CHARGER_PROP_INPUT_REGULATION_CURRENT_UA:
        return bq25628e_get_input_current_limit(dev, &value->input_current_regulation_current_ua);

    case CHARGER_PROP_INPUT_REGULATION_VOLTAGE_UV:
        return bq25628e_get_input_voltage_limit(dev, &value->input_voltage_regulation_voltage_uv);

    case CHARGER_PROP_PRESENT:
    case CHARGER_PROP_INPUT_CURRENT_NOTIFICATION:
    case CHARGER_PROP_DISCHARGE_CURRENT_NOTIFICATION:
    case CHARGER_PROP_SYSTEM_VOLTAGE_NOTIFICATION_UV:
    case CHARGER_PROP_STATUS_NOTIFICATION:
    case CHARGER_PROP_ONLINE_NOTIFICATION:
    default:
        return -ENOTSUP;
    }
}

static int bq25628e_set_prop(const struct device* dev, charger_prop_t prop,
                             const union charger_propval* value) {
    if (value == NULL) {
        return -EINVAL;
    }

    switch (prop) {
    case CHARGER_PROP_CONSTANT_CHARGE_CURRENT_UA:
        return bq25628e_set_charge_current_limit(dev, value->const_charge_current_ua);

    case CHARGER_PROP_PRECHARGE_CURRENT_UA:
        return bq25628e_set_precharge_current_limit(dev, value->precharge_current_ua);

    case CHARGER_PROP_CHARGE_TERM_CURRENT_UA:
        return bq25628e_set_termination_current_limit(dev, value->charge_term_current_ua);

    case CHARGER_PROP_CONSTANT_CHARGE_VOLTAGE_UV:
        return bq25628e_set_charge_voltage_limit(dev, value->const_charge_voltage_uv);

    case CHARGER_PROP_INPUT_REGULATION_CURRENT_UA:
        return bq25628e_set_input_current_limit(dev, value->input_current_regulation_current_ua);

    case CHARGER_PROP_INPUT_REGULATION_VOLTAGE_UV:
        return bq25628e_set_input_voltage_limit(dev, value->input_voltage_regulation_voltage_uv);

    case CHARGER_PROP_ONLINE:
    case CHARGER_PROP_PRESENT:
    case CHARGER_PROP_STATUS:
    case CHARGER_PROP_CHARGE_TYPE:
    case CHARGER_PROP_HEALTH:
    case CHARGER_PROP_INPUT_CURRENT_NOTIFICATION:
    case CHARGER_PROP_DISCHARGE_CURRENT_NOTIFICATION:
    case CHARGER_PROP_SYSTEM_VOLTAGE_NOTIFICATION_UV:
    case CHARGER_PROP_STATUS_NOTIFICATION:
    case CHARGER_PROP_ONLINE_NOTIFICATION:
    default:
        return -ENOTSUP;
    }
}

static int bq25628e_init(const struct device* dev) {
    const struct bq25628e_config* const config = dev->config;
    int ret;

    if (!i2c_is_ready_dt(&config->i2c)) {
        LOG_ERR("I2C bus is not ready");
        return -ENODEV;
    }

    ret = bq25628e_reset_registers(dev);
    if (ret < 0) {
        return ret;
    }

    ret = bq25628e_set_charge_current_limit(dev, config->ichg_ua);
    if (ret < 0) {
        return ret;
    }

    ret = bq25628e_set_charge_voltage_limit(dev, config->vreg_uv);
    if (ret < 0) {
        return ret;
    }

    if (config->iindpm_ua != 0U) {
        ret = bq25628e_set_input_current_limit(dev, config->iindpm_ua);
        if (ret < 0) {
            return ret;
        }
    }

    if (config->vindpm_uv != 0U) {
        ret = bq25628e_set_input_voltage_limit(dev, config->vindpm_uv);
        if (ret < 0) {
            return ret;
        }
    }

    ret = bq25628e_set_precharge_current_limit(dev, config->iprechg_ua);
    if (ret < 0) {
        return ret;
    }

    ret = bq25628e_set_termination_current_limit(dev, config->iterm_ua);
    if (ret < 0) {
        return ret;
    }

    ret = bq25628e_set_termination_enable(dev, !config->charge_termination_disabled);
    if (ret < 0) {
        return ret;
    }

    ret = bq25628e_set_watchdog_timer(
        dev, config->enable_watchdog ? BQ25628E_WATCHDOG_50_SEC : BQ25628E_WATCHDOG_DISABLED_SEC);
    if (ret < 0) {
        return ret;
    }

    return bq25628e_set_charge_enabled(dev, true);
}

static DEVICE_API(charger, bq25628e_driver_api) = {
    .get_property  = bq25628e_get_prop,
    .set_property  = bq25628e_set_prop,
    .charge_enable = bq25628e_charge_enable,
};

#define BQ25628E_INIT(inst)                                                                        \
    static const struct bq25628e_config bq25628e_config_##inst = {                                 \
        .i2c                         = I2C_DT_SPEC_INST_GET(inst),                                 \
        .ichg_ua                     = DT_INST_PROP(inst, constant_charge_current_max_microamp),   \
        .vreg_uv                     = DT_INST_PROP(inst, constant_charge_voltage_max_microvolt),  \
        .iindpm_ua                   = DT_INST_PROP(inst, input_current_limit_microamp),           \
        .vindpm_uv                   = DT_INST_PROP(inst, input_voltage_limit_millivolt) * 1000U,  \
        .iprechg_ua                  = DT_INST_PROP(inst, precharge_current_microamp),             \
        .iterm_ua                    = DT_INST_PROP(inst, charge_term_current_microamp),           \
        .enable_watchdog             = DT_INST_PROP(inst, enable_watchdog),                        \
        .charge_termination_disabled = DT_INST_PROP(inst, charge_termination_disabled),            \
    };                                                                                             \
    DEVICE_DT_INST_DEFINE(inst, bq25628e_init, NULL, NULL, &bq25628e_config_##inst, POST_KERNEL,   \
                          CONFIG_CHARGER_INIT_PRIORITY, &bq25628e_driver_api);

DT_INST_FOREACH_STATUS_OKAY(BQ25628E_INIT)
