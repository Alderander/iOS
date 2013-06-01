//
//  vaavudGraphHostingView.m
//  VaavudCore
//
//  Created by Andreas Okholm on 5/30/13.
//  Copyright (c) 2013 Andreas Okholm. All rights reserved.
//

#import "vaavudGraphHostingView.h"

// Support class plotIdentifier

@interface VaavudPlotIdentifier : NSObject <NSCopying, NSCoding>

@property (nonatomic) NSInteger plotType;
@property (nonatomic) NSInteger windSpeedPlotIndex;

- (id) initWithPlotType: (NSInteger) type andWindSpeedPlotIndex: (NSInteger) index;

@end

@implementation VaavudPlotIdentifier

- (id) initWithPlotType: (NSInteger) type andWindSpeedPlotIndex: (NSInteger) index
{
    self = [super init];
    if (self) {
        self.plotType = type;
        self.windSpeedPlotIndex = index;
    }
    
    return self;
}

- (id) copyWithZone:(NSZone *)zone
{
    VaavudPlotIdentifier *copy = [[[self class] alloc] init];
    
    copy.plotType = self.plotType;
    copy.windSpeedPlotIndex = self.windSpeedPlotIndex;
    
    return copy;
}


- (id) initWithCoder:(NSCoder *)aDecoder
{
    self = [super init];
    if (self) {
        self.plotType = [aDecoder decodeIntegerForKey:@"plotType"];
        self.windSpeedPlotIndex = [aDecoder decodeIntegerForKey:@"windSpeedPlotIndex"];
    }
    
    return self;
}

- (void) encodeWithCoder:(NSCoder *)aCoder
{
    [aCoder encodeInteger: self.plotType forKey:@"plotType"];
    [aCoder encodeInteger: self.plotType forKey:@"windSpeedPlotIndex"];
}

@end





@interface vaavudGraphHostingView ()


@property (nonatomic, strong)   NSMutableArray *dataForPlotX;
@property (nonatomic, strong)   NSMutableArray *dataForPlotY;

@property (nonatomic, strong)   CPTGraph    *graph;
@property (nonatomic, strong)   CPTXYPlotSpace *plotSpace;
@property (nonatomic)           float       graphTimeWidth;
@property (nonatomic)           float       graphMinWindspeedWidth;
@property (nonatomic, strong)   NSDate      *startTime;
@property (nonatomic)           float       graphYMinValue;
@property (nonatomic)           float       graphYMaxValue;
@property (nonatomic)           NSUInteger  windSpeedPlotCounter;
@property (nonatomic)           double      startTimeDifference;

@property (nonatomic) BOOL      wasValid;


enum plotName : NSUInteger {
    averagePlot = 0,
    windSpeedPlot = 1
};


@end

@implementation vaavudGraphHostingView

- (id)initWithFrame:(CGRect)frame
{
    self = [super initWithFrame:frame];
    if (self) {
        // Initialization code
    }
    return self;
}


- (void) shiftGraphX
{
    if ([[self.vaavudCoreController.isValid lastObject] boolValue]) {
        float timeSinceStart = - [self.startTime  timeIntervalSinceNow] - self.startTimeDifference + 1; // graph - x range should always be 1 second ahead.
        
        if (timeSinceStart > self.graphTimeWidth) {
            self.plotSpace.xRange  = [CPTPlotRange plotRangeWithLocation: CPTDecimalFromFloat(timeSinceStart - self.graphTimeWidth) length:CPTDecimalFromFloat(self.graphTimeWidth)];
            self.plotSpace.globalXRange = [CPTPlotRange plotRangeWithLocation: CPTDecimalFromFloat(0) length: CPTDecimalFromFloat(timeSinceStart)];
        }
    }
}


- (void) addDataPoint
{
    
    BOOL updateYRange = NO; // by default do not update y-range
    
    // Check if there is a new point to add
    NSNumber *x = [self.vaavudCoreController.windSpeedTime lastObject];
    NSNumber *lastX = [[self.dataForPlotX lastObject] lastObject];
    
    if (!lastX) { // first datapoint in plot
        lastX = [NSNumber numberWithFloat:-1];
        
        if (!self.startTime) { // ONLY set once
            self.startTime = [NSDate dateWithTimeIntervalSinceNow: - [x doubleValue]];
            self.startTimeDifference = [x doubleValue];
            
             NSNumber *y = [self.vaavudCoreController.windSpeed lastObject];
            self.graphYMinValue = [y floatValue];
            self.graphYMaxValue = [y floatValue];
            
            updateYRange = YES; // update Y range if first time;
        }
    }
    
    
    if (![x isEqualToNumber: lastX])
    {
            
        NSNumber *y = [self.vaavudCoreController.windSpeed lastObject];
        NSNumber *xZeroShifted = [NSNumber numberWithDouble:([x doubleValue] - self.startTimeDifference) ];
        
        [[self.dataForPlotX objectAtIndex: self.windSpeedPlotCounter] addObject: xZeroShifted];
        [[self.dataForPlotY objectAtIndex: self.windSpeedPlotCounter] addObject: y];
        
        
        // update min and max values
        if ([y floatValue] > self.graphYMaxValue) {
            self.graphYMaxValue = [y floatValue];
            updateYRange = YES;
        }
            
        
        if ([y floatValue] < self.graphYMinValue) {
            self.graphYMinValue = [y floatValue];
            updateYRange = YES;
        }
            
        
        if (updateYRange)
        {
            float graphYLowerBound;
            float graphYwidth;
            
            // determine y window range
            if (self.graphYMinValue < 2)
                graphYLowerBound = 0;
            else
                graphYLowerBound = floor(self.graphYMinValue);
            
            graphYwidth = floor(self.graphYMaxValue) +1 - graphYLowerBound;
            
            if (graphYwidth < self.graphMinWindspeedWidth)
                graphYwidth = self.graphMinWindspeedWidth;
            
            CPTPlotRange *plotRange = [CPTPlotRange plotRangeWithLocation: CPTDecimalFromFloat(graphYLowerBound) length:CPTDecimalFromFloat(graphYwidth)];
            
            self.plotSpace.yRange  = plotRange;
            self.plotSpace.globalYRange = plotRange;
        }
        
        [self.graph reloadData];
    }
}



- (void) createNewPlot
{

    if ( ![self.dataForPlotX count] == 0 ) {
        self.windSpeedPlotCounter++;
    }
        
    // Create a blue plot area
    CPTScatterPlot *windSpeedLinePlot       = [[CPTScatterPlot alloc] init];
    CPTMutableLineStyle *lineStyle      = [CPTMutableLineStyle lineStyle];
    lineStyle.miterLimit                = 1.0f;
    lineStyle.lineWidth                 = 3.0f;
    //    boundLinePlot.interpolation         = CPTScatterPlotInterpolationCurved;
    CPTColor *vaavudBlue = [[CPTColor alloc] initWithComponentRed: 0 green: (float) 174/255 blue: (float) 239/255 alpha: 1 ];
    
    
    lineStyle.lineColor         = vaavudBlue;
    windSpeedLinePlot.dataLineStyle = lineStyle;
//    boundLinePlot.identifier    = [NSNumber numberWithInt: self.windSpeedPlotCounter];
    windSpeedLinePlot.identifier    = [[VaavudPlotIdentifier alloc] initWithPlotType: windSpeedPlot andWindSpeedPlotIndex: self.windSpeedPlotCounter];
    windSpeedLinePlot.dataSource    = self;
    [self.dataForPlotX insertObject: [NSMutableArray arrayWithCapacity:1] atIndex: self.windSpeedPlotCounter];
    [self.dataForPlotY insertObject: [NSMutableArray arrayWithCapacity:1] atIndex: self.windSpeedPlotCounter];

    [self.graph addPlot:boundLinePlot];
}



- (void) setupCorePlotGraph
{
    
    self.windSpeedPlotCounter = 0;
    self.startTime = nil;
    self.graphYMaxValue = 0;
    self.graphYMinValue = 0;
    self.dataForPlotX = [NSMutableArray arrayWithCapacity:1];
    self.dataForPlotY = [NSMutableArray arrayWithCapacity:1];

    self.wasValid = NO;
    
    
    // TEMPORATY LOAD OF CONSTANTS
    self.graphTimeWidth = 16;
    self.graphMinWindspeedWidth = 4;
    
    self.collapsesLayers = NO; // Setting to YES reduces GPU memory usage, but can slow drawing/scrolling
    
    // Create graph from theme
    self.graph = [[CPTXYGraph alloc] initWithFrame:CGRectZero];
    self.hostedGraph     = self.graph;
    
    self.graph.fill = nil;
    self.graph.plotAreaFrame.fill = nil;
    self.graph.plotAreaFrame.borderLineStyle = nil;
    
    //    [self.view addSubview:self.hostView];
    
    self.graph.paddingLeft   = 0.0;
    self.graph.paddingTop    = 0.0;
    self.graph.paddingRight  = 0.0;
    self.graph.paddingBottom = 0.0;
    self.graph.plotAreaFrame.paddingTop     = 10.0;
    self.graph.plotAreaFrame.paddingLeft    = 30.0;
    self.graph.plotAreaFrame.paddingBottom  = 30.0;
    
    // Setup plot space
    self.plotSpace = (CPTXYPlotSpace *) self.graph.defaultPlotSpace;
    self.plotSpace.allowsUserInteraction = YES;
    self.plotSpace.xRange                = [CPTPlotRange plotRangeWithLocation:CPTDecimalFromFloat(0.0) length:CPTDecimalFromFloat(self.graphTimeWidth)];
    self.plotSpace.yRange                = [CPTPlotRange plotRangeWithLocation:CPTDecimalFromFloat(0.0) length:CPTDecimalFromFloat(self.graphMinWindspeedWidth)];
    self.plotSpace.GlobalXRange          = [CPTPlotRange plotRangeWithLocation:CPTDecimalFromFloat(0.0) length:CPTDecimalFromFloat(self.graphTimeWidth)];
    self.plotSpace.GlobalYRange          = [CPTPlotRange plotRangeWithLocation:CPTDecimalFromFloat(0.0) length:CPTDecimalFromFloat(self.graphMinWindspeedWidth)];
    self.plotSpace.delegate = self;
    
    // Axes
    
    CPTMutableLineStyle *majorGridLineStyle = [CPTMutableLineStyle lineStyle];
    majorGridLineStyle.lineWidth        = 1.5;
    majorGridLineStyle.lineColor        = [CPTColor lightGrayColor];
    
    CPTMutableLineStyle *GreyLineStyle = [CPTMutableLineStyle lineStyle];
    GreyLineStyle.lineWidth        = 1.5;
    GreyLineStyle.lineColor        = [CPTColor grayColor];
    
    
    CPTMutableTextStyle *textStyleDarkGrey = [CPTMutableTextStyle textStyle];
    textStyleDarkGrey.color                = [CPTColor darkGrayColor];
    
    CPTMutableTextStyle *textStyleGrey  = [CPTMutableTextStyle textStyle];
    textStyleGrey.color                 = [CPTColor grayColor];
    
    NSNumberFormatter *numberFormat     = [[NSNumberFormatter alloc] init];
    [numberFormat setMaximumFractionDigits: 0];
    
    CPTXYAxisSet *axisSet               = (CPTXYAxisSet *) self.graph.axisSet;
    CPTXYAxis *x                        = axisSet.xAxis;
    x.majorIntervalLength               = CPTDecimalFromInt(5);
    x.minorTicksPerInterval             = 0;
    x.axisConstraints                   = [CPTConstraints constraintWithLowerOffset:0.0];
    x.labelTextStyle                    = textStyleGrey;
    x.axisLineStyle                     = GreyLineStyle;
    x.majorTickLineStyle                = GreyLineStyle;
    x.minorTickLineStyle                = GreyLineStyle;
    x.labelFormatter                    = numberFormat;
    x.majorTickLineStyle                = nil;
    
    
    CPTXYAxis *y                        = axisSet.yAxis;
    y.majorIntervalLength               = CPTDecimalFromInt(2);
    y.minorTicksPerInterval             = 0;
    y.axisConstraints                   = [CPTConstraints constraintWithLowerOffset:0.0];
    y.labelFormatter                    = numberFormat;
    y.majorGridLineStyle                = majorGridLineStyle;
    y.labelTextStyle                    = textStyleDarkGrey;
    y.minorTickLineStyle                = nil;
    y.majorTickLineStyle                = nil;
    y.axisLineStyle                     = nil;
    
    
    
    
    
    
    
    // create Red Average  // Create a blue plot area
    CPTScatterPlot *averageLinePlot       = [[CPTScatterPlot alloc] init];
    CPTMutableLineStyle *lineStyle      = [CPTMutableLineStyle lineStyle];
    lineStyle.miterLimit                = 1.0f;
    lineStyle.lineWidth                 = 3.0f;
    CPTColor *vaavudRed = [[CPTColor alloc] initWithComponentRed: (float) 210/255 green: (float) 37/255 blue: (float) 45/255 alpha: 1 ];
    
    
    //   lineStyle.lineColor         = [CPTColor whiteColor];
    lineStyle.lineColor         = vaavudRed;
    averageLinePlot.dataLineStyle = lineStyle;
    averageLinePlot.identifier    = [[VaavudPlotIdentifier alloc] initWithPlotType: averagePlot andWindSpeedPlotIndex:0];
//    [NSNumber numberWithInt: averagePlot];
    averageLinePlot.dataSource    = self;
//    [self.dataForPlot insertObject: [NSMutableArray arrayWithCapacity:1] atIndex: averagePlot];
    [self.graph addPlot:averageLinePlot];
    
    
}

-(NSUInteger)numberOfRecordsForPlot:(CPTPlot *)plot
{
 
    VaavudPlotIdentifier *plotIdentity = plot.identifier;
    
    switch (plotIdentity.plotType) {
        case averagePlot:
            return (NSUInteger) 2;
            break;
            
        case windSpeedPlot:
            return [[self.dataForPlotX objectAtIndex: plotIdentity.windSpeedPlotIndex] count];
            break;
        default:
            NSLog( @"We fucked up");
            return 0;
            break;
    }
    
//    VaavudPlotIdentifier = plot.identifier;
//    NSUInteger mainIndex = [(NSNumber *) plot.identifier integerValue];
//    NSUInteger count = [[self.dataForPlot objectAtIndex: mainIndex] count];
//    return count;
    
}



//-(NSNumber *)numberForPlot:(CPTPlot *)plot field:(NSUInteger)fieldEnum recordIndex:(NSUInteger)index
//{
//    
//    NSString *key = (fieldEnum == CPTScatterPlotFieldX ? @"x" : @"y");
//    NSUInteger mainIndex = [(NSNumber *) plot.identifier integerValue];
//    NSNumber *num = [[[self.dataForPlot objectAtIndex:mainIndex] objectAtIndex: index] valueForKey:key];
//    
//    return num;
//    
//    
//}


- (NSArray *) numbersForPlot: (CPTPlot *)plot field:(NSUInteger) fieldEnum recordIndexRange: (NSRange)indexRange
{
    VaavudPlotIdentifier *plotIdentity = plot.identifier;
    
    NSArray *numbers;
    
    switch (plotIdentity.plotType) {
        case averagePlot:
            
            if (fieldEnum == CPTScatterPlotFieldX) {
                numbers = [NSArray arrayWithObjects: [NSNumber numberWithDouble:0], [[self.dataForPlotX lastObject] lastObject], nil];
            } else {
                NSNumber *windspeedAverage = [self.vaavudCoreController getAverage];
                numbers = [NSArray arrayWithObjects: windspeedAverage, windspeedAverage, nil];
            }
            break;
            
        case windSpeedPlot:
            
            if (fieldEnum == CPTScatterPlotFieldX) {
                numbers = [[self.dataForPlotX objectAtIndex:plotIdentity.windSpeedPlotIndex] subarrayWithRange: indexRange];
            } else {
                numbers = [[self.dataForPlotY objectAtIndex:plotIdentity.windSpeedPlotIndex] subarrayWithRange: indexRange];
            }
            break;
        default:
            NSLog( @"We fucked up");
            break;
    }
    
    return numbers;
    
//    if(plotIdentity.plotType )
//    
//    NSUInteger mainIndex = [(NSNumber *) plot.identifier integerValue];
//    
//    NSArray *numbers;
//    
//    if (fieldEnum == CPTScatterPlotFieldX) {
//        numbers= [[self.dataForPlot objectAtIndex:mainIndex] subarrayWithRange: indexRange];
//    } else
//    
//    
//    return  numbers;
    
    
}



// only displace in X
-(CGPoint)plotSpace:(CPTPlotSpace *)space willDisplaceBy:(CGPoint)displacement{
    return CGPointMake(displacement.x,0);}

// do not zoom in Y
-(CPTPlotRange *)plotSpace:(CPTPlotSpace *)space willChangePlotRangeTo:(CPTPlotRange *)newRange forCoordinate:(CPTCoordinate)coordinate{
    if (coordinate == CPTCoordinateY) {
        newRange = ((CPTXYPlotSpace*)space).yRange;
    }
    return newRange;}

/*
// Only override drawRect: if you perform custom drawing.
// An empty implementation adversely affects performance during animation.
- (void)drawRect:(CGRect)rect
{
    // Drawing code
}
*/

@end
