export type Trip={id:string;share_token:string;name:string;start_date:string;end_date:string;status:'active'|'archived';created_by:string|null;created_at:string};
export type Participant={id:string;trip_id:string;user_id:string;display_name:string;is_admin:boolean;created_at:string};
export type Ingredient={id:string;meal_id:string;name:string;quantity:number;unit:string|null;added_to_shopping:boolean};
export type Meal={id:string;trip_id:string;date:string;meal_type:string;title:string;notes:string|null;ingredients?:Ingredient[]};
export type ShoppingItem={id:string;trip_id:string;name:string;quantity:number;unit:string|null;category:'food'|'drinks'|'boat'|'other';meal_id:string|null;meal_ingredient_id:string|null;status:'not_bought'|'bought';bought_by:string|null;version:number;buyer?:{display_name:string}|null;meal?:{title:string}|null};
export type Audit={id:string;created_at:string;participant_name:string|null;action_type:string;entity_type:string;old_value:unknown;new_value:unknown};
