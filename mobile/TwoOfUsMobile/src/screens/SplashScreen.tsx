import React, {useEffect, useRef} from 'react';
import {View, Text, StyleSheet, Animated, Easing} from 'react-native';

export default function SplashScreen({navigation}: any) {
  const fade = useRef(new Animated.Value(0)).current;
  const scale = useRef(new Animated.Value(0.75)).current;
  const subtitleFade = useRef(new Animated.Value(0)).current;
  const subtitleY = useRef(new Animated.Value(12)).current;
  const heartScale = useRef(new Animated.Value(1)).current;
  const glowOpacity = useRef(new Animated.Value(0.3)).current;

  const pulseHeart = () => {
    Animated.loop(
      Animated.sequence([
        Animated.timing(heartScale, {
          toValue: 1.25,
          duration: 600,
          easing: Easing.inOut(Easing.ease),
          useNativeDriver: true,
        }),
        Animated.timing(heartScale, {
          toValue: 1,
          duration: 600,
          easing: Easing.inOut(Easing.ease),
          useNativeDriver: true,
        }),
      ]),
    ).start();

    Animated.loop(
      Animated.sequence([
        Animated.timing(glowOpacity, {
          toValue: 0.8,
          duration: 600,
          useNativeDriver: true,
        }),
        Animated.timing(glowOpacity, {
          toValue: 0.2,
          duration: 600,
          useNativeDriver: true,
        }),
      ]),
    ).start();
  };

  useEffect(() => {
    Animated.sequence([
      Animated.parallel([
        Animated.timing(fade, {
          toValue: 1,
          duration: 800,
          easing: Easing.out(Easing.cubic),
          useNativeDriver: true,
        }),
        Animated.spring(scale, {
          toValue: 1,
          tension: 60,
          friction: 7,
          useNativeDriver: true,
        }),
      ]),
      Animated.parallel([
        Animated.timing(subtitleFade, {
          toValue: 1,
          duration: 500,
          useNativeDriver: true,
        }),
        Animated.timing(subtitleY, {
          toValue: 0,
          duration: 500,
          easing: Easing.out(Easing.quad),
          useNativeDriver: true,
        }),
      ]),
    ]).start(() => pulseHeart());

    const timer = setTimeout(() => navigation.replace('Login'), 3000);
    return () => clearTimeout(timer);
  }, []);

  return (
    <View style={styles.container}>
      <Animated.View style={{opacity: glowOpacity, ...styles.glow}} />

      <Animated.View
        style={{
          opacity: fade,
          transform: [{scale}],
          alignItems: 'center',
        }}>
        <View style={styles.logoRow}>
          <Text style={styles.logo}>TwoOfUs</Text>
          <Animated.Text
            style={[styles.heart, {transform: [{scale: heartScale}]}]}>
            ♥
          </Animated.Text>
        </View>

        <Animated.View
          style={{
            opacity: subtitleFade,
            transform: [{translateY: subtitleY}],
          }}>
          <Text style={styles.subtitle}>Private • Secure • Together</Text>
        </Animated.View>
      </Animated.View>

      <Animated.View style={[styles.dot, {opacity: subtitleFade}]} />
    </View>
  );
}

const styles = StyleSheet.create({
  container: {
    flex: 1,
    backgroundColor: '#07111F',
    justifyContent: 'center',
    alignItems: 'center',
  },
  glow: {
    position: 'absolute',
    width: 280,
    height: 280,
    borderRadius: 140,
    backgroundColor: '#4F8CFF',
    transform: [{scaleX: 2.5}, {scaleY: 0.6}],
    top: '35%',
  },
  logoRow: {
    flexDirection: 'row',
    alignItems: 'center',
    gap: 10,
    marginBottom: 14,
  },
  logo: {
    color: '#4F8CFF',
    fontSize: 48,
    fontWeight: '800',
    letterSpacing: -1,
  },
  heart: {
    color: '#FF6B8A',
    fontSize: 36,
  },
  subtitle: {
    color: '#94A3B8',
    fontSize: 15,
    letterSpacing: 1.5,
    textAlign: 'center',
  },
  dot: {
    position: 'absolute',
    bottom: 60,
    width: 6,
    height: 6,
    borderRadius: 3,
    backgroundColor: '#4F8CFF',
  },
});